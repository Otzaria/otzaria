use std::{
    cell::RefCell,
    collections::HashMap,
    ffi::c_void,
    mem::{size_of, ManuallyDrop},
    panic::{catch_unwind, resume_unwind, AssertUnwindSafe},
    ptr::null,
    rc::Rc,
    sync::{
        atomic::{AtomicIsize, AtomicUsize, Ordering},
        Arc, Mutex,
    },
    thread,
    time::Duration,
};

use irondash_message_channel::Value;
use irondash_run_loop::RunLoop;
use windows::{
    core::{implement, ComInterface, IUnknown, HRESULT, HSTRING},
    Win32::{
        Foundation::{
            BOOL, DATA_S_SAMEFORMATETC, DV_E_FORMATETC, E_NOTIMPL, OLE_E_ADVISENOTSUPPORTED, S_OK,
        },
        Graphics::{
            Gdi::{
                DeleteObject, GetObjectW, BITMAP, BITMAPINFOHEADER, BITMAPV5HEADER, BI_BITFIELDS,
                BI_RGB, HBITMAP, LCS_GM_IMAGES,
            },
            Imaging::{
                CLSID_WICImagingFactory, GUID_WICPixelFormat32bppRGBA, IWICImagingFactory,
                WICBitmapDitherTypeNone, WICBitmapPaletteTypeCustom,
            },
        },
        System::{
            Com::{
                CoGetApartmentType, CoTaskMemFree, IAdviseSink, IDataObject, IDataObject_Impl,
                IEnumFORMATETC, IEnumSTATDATA, ISequentialStream, ISequentialStream_Impl, APTTYPE,
                APTTYPEQUALIFIER, DATADIR_GET, FORMATETC, STGMEDIUM, STGMEDIUM_0, TYMED_GDI,
                TYMED_HGLOBAL, TYMED_ISTREAM,
            },
            DataExchange::RegisterClipboardFormatW,
            Ole::{
                OleGetClipboard, OleInitialize, OleSetClipboard, OleUninitialize, CF_BITMAP,
                CF_DIB, CF_DIBV5, CF_UNICODETEXT,
            },
        },
        UI::Shell::{SHCreateMemStream, SHCreateStdEnumFmtEtc},
    },
};

use super::super::common::{
    as_u8_slice, create_instance, format_to_string, image_data_to_hbitmap, make_format_with_tymed,
};
use super::{dib_to_bmp_pixel_offset, snapshot_bitmap, PlatformDataReader, PngSource};
use crate::api_model::ImageData;

const TWO_FRAME_GIF: &[u8] = &[
    0x47, 0x49, 0x46, 0x38, 0x39, 0x61, 0x01, 0x00, 0x01, 0x00, 0x80, 0x00, 0x00, 0xff, 0x00, 0x00,
    0x00, 0x00, 0xff, 0x21, 0xff, 0x0b, 0x4e, 0x45, 0x54, 0x53, 0x43, 0x41, 0x50, 0x45, 0x32, 0x2e,
    0x30, 0x03, 0x01, 0x00, 0x00, 0x00, 0x21, 0xf9, 0x04, 0x00, 0x0a, 0x00, 0x00, 0x00, 0x2c, 0x00,
    0x00, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00, 0x02, 0x02, 0x44, 0x01, 0x00, 0x21, 0xf9, 0x04,
    0x00, 0x0a, 0x00, 0x00, 0x00, 0x2c, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00, 0x02,
    0x02, 0x4c, 0x01, 0x00, 0x3b,
];

struct OleApartment;

impl OleApartment {
    fn new() -> Self {
        unsafe { OleInitialize(None) }.unwrap();
        Self
    }
}

impl Drop for OleApartment {
    fn drop(&mut self) {
        unsafe { OleUninitialize() };
    }
}

#[derive(Clone, Copy)]
enum MediumKind {
    SystemOwned,
    CustomOwner,
    NullBitmap,
    InvalidBitmap,
    WrongTymed,
}

#[derive(Default)]
struct Observations {
    requested: Mutex<Vec<(u16, u32)>>,
    releases: AtomicUsize,
    last_original: AtomicIsize,
}

#[implement(ISequentialStream)]
struct MediumOwner {
    bitmap: HBITMAP,
    owns_bitmap: bool,
    observations: Arc<Observations>,
}

impl Drop for MediumOwner {
    fn drop(&mut self) {
        self.observations.releases.fetch_add(1, Ordering::SeqCst);
        if self.owns_bitmap {
            assert!(unsafe { DeleteObject(self.bitmap) }.as_bool());
        }
    }
}

#[allow(non_snake_case)]
impl ISequentialStream_Impl for MediumOwner {
    fn Read(&self, _: *mut c_void, _: u32, _: *mut u32) -> HRESULT {
        E_NOTIMPL
    }
    fn Write(&self, _: *const c_void, _: u32, _: *mut u32) -> HRESULT {
        E_NOTIMPL
    }
}

#[implement(IDataObject)]
struct BitmapDataObject {
    formats: Vec<FORMATETC>,
    bytes: HashMap<u16, Vec<u8>>,
    pixels: Vec<u8>,
    medium_kind: MediumKind,
    observations: Arc<Observations>,
}

impl BitmapDataObject {
    fn bitmap(kind: MediumKind, pixels: Vec<u8>) -> Self {
        Self {
            formats: vec![make_format_with_tymed(CF_BITMAP.0 as u32, TYMED_GDI)],
            bytes: HashMap::new(),
            pixels,
            medium_kind: kind,
            observations: Arc::default(),
        }
    }

    fn with_bytes(mut self, format: u32, bytes: Vec<u8>) -> Self {
        self.formats
            .push(make_format_with_tymed(format, TYMED_ISTREAM));
        self.bytes.insert(format as u16, bytes);
        self
    }

    fn into_reader(self) -> (Rc<PlatformDataReader>, Arc<Observations>) {
        let observations = self.observations.clone();
        let object: IDataObject = self.into();
        (
            PlatformDataReader::new_with_data_object(object, None),
            observations,
        )
    }

    fn bitmap_medium(&self) -> STGMEDIUM {
        let bitmap = match self.medium_kind {
            MediumKind::NullBitmap => HBITMAP::default(),
            MediumKind::InvalidBitmap => HBITMAP(1),
            _ => image_data_to_hbitmap(&ImageData {
                width: 4,
                height: 4,
                bytes_per_row: 16,
                data: self.pixels.clone(),
                device_pixel_ratio: None,
            })
            .unwrap(),
        };
        self.observations
            .last_original
            .store(bitmap.0, Ordering::SeqCst);
        let owner: Option<IUnknown> = if matches!(self.medium_kind, MediumKind::SystemOwned) {
            None
        } else {
            let owner: ISequentialStream = MediumOwner {
                bitmap,
                owns_bitmap: !matches!(
                    self.medium_kind,
                    MediumKind::NullBitmap | MediumKind::InvalidBitmap
                ),
                observations: self.observations.clone(),
            }
            .into();
            Some(owner.cast().unwrap())
        };
        STGMEDIUM {
            tymed: if matches!(self.medium_kind, MediumKind::WrongTymed) {
                TYMED_HGLOBAL.0 as u32
            } else {
                TYMED_GDI.0 as u32
            },
            u: STGMEDIUM_0 { hBitmap: bitmap },
            pUnkForRelease: ManuallyDrop::new(owner),
        }
    }
}

#[allow(non_snake_case)]
impl IDataObject_Impl for BitmapDataObject {
    fn GetData(&self, requested: *const FORMATETC) -> windows::core::Result<STGMEDIUM> {
        let requested = unsafe { &*requested };
        self.observations
            .requested
            .lock()
            .unwrap()
            .push((requested.cfFormat, requested.tymed));
        if requested.cfFormat == CF_BITMAP.0 && requested.tymed == TYMED_GDI.0 as u32 {
            return Ok(self.bitmap_medium());
        }
        let bytes = self
            .bytes
            .get(&requested.cfFormat)
            .ok_or_else(|| windows::core::Error::from(DV_E_FORMATETC))?;
        if requested.tymed & TYMED_ISTREAM.0 as u32 == 0 {
            return Err(DV_E_FORMATETC.into());
        }
        let stream = unsafe { SHCreateMemStream(Some(bytes)) }.unwrap();
        Ok(STGMEDIUM {
            tymed: TYMED_ISTREAM.0 as u32,
            u: STGMEDIUM_0 {
                pstm: ManuallyDrop::new(Some(stream)),
            },
            pUnkForRelease: ManuallyDrop::new(None),
        })
    }

    fn GetDataHere(&self, _: *const FORMATETC, _: *mut STGMEDIUM) -> windows::core::Result<()> {
        Err(E_NOTIMPL.into())
    }
    fn QueryGetData(&self, requested: *const FORMATETC) -> HRESULT {
        let requested = unsafe { &*requested };
        if self
            .formats
            .iter()
            .any(|f| f.cfFormat == requested.cfFormat && f.tymed & requested.tymed != 0)
        {
            S_OK
        } else {
            DV_E_FORMATETC
        }
    }
    fn GetCanonicalFormatEtc(&self, input: *const FORMATETC, output: *mut FORMATETC) -> HRESULT {
        unsafe { *output = *input };
        DATA_S_SAMEFORMATETC
    }
    fn SetData(
        &self,
        _: *const FORMATETC,
        _: *const STGMEDIUM,
        _: BOOL,
    ) -> windows::core::Result<()> {
        Err(E_NOTIMPL.into())
    }
    fn EnumFormatEtc(&self, direction: u32) -> windows::core::Result<IEnumFORMATETC> {
        if direction == DATADIR_GET.0 as u32 {
            unsafe { SHCreateStdEnumFmtEtc(&self.formats) }
        } else {
            Err(E_NOTIMPL.into())
        }
    }
    fn DAdvise(
        &self,
        _: *const FORMATETC,
        _: u32,
        _: Option<&IAdviseSink>,
    ) -> windows::core::Result<u32> {
        Err(OLE_E_ADVISENOTSUPPORTED.into())
    }
    fn DUnadvise(&self, _: u32) -> windows::core::Result<()> {
        Err(OLE_E_ADVISENOTSUPPORTED.into())
    }
    fn EnumDAdvise(&self) -> windows::core::Result<IEnumSTATDATA> {
        Err(OLE_E_ADVISENOTSUPPORTED.into())
    }
}

fn pattern(alpha: u8) -> Vec<u8> {
    (0..16)
        .flat_map(|i| [i * 13, 255 - i * 11, i * 7, alpha])
        .collect()
}

fn bitmap_alive(bitmap: HBITMAP) -> bool {
    let mut data = BITMAP::default();
    (unsafe {
        GetObjectW(
            bitmap,
            size_of::<BITMAP>() as i32,
            Some(&mut data as *mut _ as *mut c_void),
        )
    }) != 0
}

fn registered(name: &str) -> u32 {
    unsafe { RegisterClipboardFormatW(&HSTRING::from(name)) }
}

fn read(reader: Rc<PlatformDataReader>, format: u32) -> Vec<u8> {
    let result = Rc::new(RefCell::new(None));
    let captured = result.clone();
    let run_loop = RunLoop::current();
    let _timeout = run_loop.schedule(Duration::from_secs(10), || RunLoop::current().stop());
    let _task = run_loop.spawn(async move {
        captured.replace(Some(
            reader
                .get_data_for_item(0, format_to_string(format), None)
                .await,
        ));
        RunLoop::current().stop();
    });
    run_loop.run();
    let result = result
        .borrow_mut()
        .take()
        .expect("Reader did not complete before timeout")
        .unwrap();
    match result {
        Value::U8List(bytes) => bytes,
        other => panic!("Expected image bytes, got {other:?}"),
    }
}

fn decode_png(bytes: &[u8]) -> Vec<u8> {
    let factory: IWICImagingFactory = create_instance(&CLSID_WICImagingFactory).unwrap();
    unsafe {
        let stream = SHCreateMemStream(Some(bytes)).unwrap();
        let decoder = factory
            .CreateDecoderFromStream(&stream, null(), Default::default())
            .unwrap();
        let frame = decoder.GetFrame(0).unwrap();
        let (mut width, mut height) = (0, 0);
        frame.GetSize(&mut width, &mut height).unwrap();
        assert_eq!((width, height), (4, 4));
        let converter = factory.CreateFormatConverter().unwrap();
        converter
            .Initialize(
                &frame,
                &GUID_WICPixelFormat32bppRGBA,
                WICBitmapDitherTypeNone,
                None,
                0.0,
                WICBitmapPaletteTypeCustom,
            )
            .unwrap();
        let mut pixels = vec![0; 64];
        converter.CopyPixels(null(), 16, &mut pixels).unwrap();
        pixels
    }
}

fn dib(pixels: &[u8], v5: bool) -> Vec<u8> {
    let mut data = if v5 {
        let header = BITMAPV5HEADER {
            bV5Size: size_of::<BITMAPV5HEADER>() as u32,
            bV5Width: 4,
            bV5Height: -4,
            bV5Planes: 1,
            bV5BitCount: 32,
            bV5Compression: BI_BITFIELDS,
            bV5SizeImage: 64,
            bV5RedMask: 0x00ff0000,
            bV5GreenMask: 0x0000ff00,
            bV5BlueMask: 0x000000ff,
            bV5AlphaMask: 0xff000000,
            bV5CSType: 0x73524742,
            bV5Intent: LCS_GM_IMAGES as u32,
            ..Default::default()
        };
        unsafe { as_u8_slice(&header) }.to_vec()
    } else {
        let header = BITMAPINFOHEADER {
            biSize: size_of::<BITMAPINFOHEADER>() as u32,
            biWidth: 4,
            biHeight: -4,
            biPlanes: 1,
            biBitCount: 32,
            biCompression: BI_RGB.0,
            biSizeImage: 64,
            ..Default::default()
        };
        unsafe { as_u8_slice(&header) }.to_vec()
    };
    for pixel in pixels.chunks_exact(4) {
        data.extend_from_slice(&[pixel[2], pixel[1], pixel[0], pixel[3]]);
    }
    data
}

#[test]
fn bitmap_dib_offsets_include_palette_and_external_masks() {
    fn layout(header: u32, bits: u16, compression: u32, used: u32, prefix: usize) -> Vec<u8> {
        let mut data = vec![0; prefix + 4];
        data[..4].copy_from_slice(&header.to_le_bytes());
        if header == 12 {
            data[10..12].copy_from_slice(&bits.to_le_bytes());
        } else {
            data[14..16].copy_from_slice(&bits.to_le_bytes());
            data[16..20].copy_from_slice(&compression.to_le_bytes());
            data[32..36].copy_from_slice(&used.to_le_bytes());
        }
        data
    }
    for (header, bits, compression, used, prefix) in [
        (12, 1, 0, 0, 18),
        (12, 24, 0, 0, 12),
        (40, 8, 0, 0, 1064),
        (40, 8, 0, 2, 48),
        (40, 24, 0, 3, 52),
        (40, 32, 3, 0, 52),
        (40, 32, 6, 0, 56),
        (108, 32, 3, 0, 108),
        (124, 32, 3, 0, 124),
        (124, 8, 0, 2, 132),
    ] {
        assert_eq!(
            dib_to_bmp_pixel_offset(&layout(header, bits, compression, used, prefix)),
            Some(prefix as u32 + 14)
        );
    }
}

#[test]
fn bitmap_dib_offsets_reject_truncated_and_overflowing_layouts() {
    let original = dib(&pattern(127), true);
    for length in 0..=124 {
        assert!(dib_to_bmp_pixel_offset(&original[..length]).is_none());
    }
    for (at, value) in [(0, 125u32), (0, u32::MAX), (32, u32::MAX), (32, 17)] {
        let mut data = original.clone();
        data[at..at + 4].copy_from_slice(&value.to_le_bytes());
        assert!(dib_to_bmp_pixel_offset(&data).is_none());
    }
    let mut indexed = original.clone();
    indexed[14..16].copy_from_slice(&1u16.to_le_bytes());
    indexed[32..36].copy_from_slice(&3u32.to_le_bytes());
    assert!(dib_to_bmp_pixel_offset(&indexed).is_none());
    let mut masks = dib(&pattern(255), false);
    masks[16..20].copy_from_slice(&3u32.to_le_bytes());
    masks.truncate(51);
    assert!(dib_to_bmp_pixel_offset(&masks).is_none());
}

#[test]
fn bitmap_dib_offsets_keep_packed_v5_profiles_after_pixels() {
    let mut data = dib(&pattern(127), true);
    let profile_offset = data.len() as u32;
    data[56..60].copy_from_slice(&0x4d424544u32.to_le_bytes());
    data[112..116].copy_from_slice(&profile_offset.to_le_bytes());
    data[116..120].copy_from_slice(&4u32.to_le_bytes());
    data.extend_from_slice(&[0; 4]);
    assert_eq!(dib_to_bmp_pixel_offset(&data), Some(138));
    for (at, value) in [
        (112, 124u32),
        (112, u32::MAX),
        (116, 0),
        (116, 5),
        (4, u32::MAX),
        (8, i32::MIN as u32),
    ] {
        let mut invalid = data.clone();
        invalid[at..at + 4].copy_from_slice(&value.to_le_bytes());
        assert!(dib_to_bmp_pixel_offset(&invalid).is_none());
    }
}

#[test]
fn bitmap_dib_palette_preserves_every_pixel() {
    let _ole = OleApartment::new();
    let mut data = dib(&pattern(255), false);
    data.truncate(40);
    data[14..16].copy_from_slice(&8u16.to_le_bytes());
    data[20..24].copy_from_slice(&16u32.to_le_bytes());
    data[32..36].copy_from_slice(&2u32.to_le_bytes());
    data.extend_from_slice(&[0, 0, 255, 0, 0, 255, 0, 0]);
    data.extend_from_slice(&[0, 1, 1, 0].repeat(4));
    let (reader, _) = BitmapDataObject::bitmap(MediumKind::CustomOwner, vec![0; 64])
        .with_bytes(CF_DIB.0 as u32, data)
        .into_reader();
    let png = read(reader, registered("PNG"));
    assert_eq!(
        decode_png(&png),
        vec![255, 0, 0, 255, 0, 255, 0, 255, 0, 255, 0, 255, 255, 0, 0, 255].repeat(4)
    );
}

#[test]
fn bitmap_dib_external_masks_preserve_every_pixel() {
    let _ole = OleApartment::new();
    let mut data = dib(&pattern(0), false);
    data[16..20].copy_from_slice(&3u32.to_le_bytes());
    let masks = [0x00ff0000u32, 0x0000ff00, 0x000000ff]
        .into_iter()
        .flat_map(u32::to_le_bytes);
    data.splice(40..40, masks);
    let (reader, _) = BitmapDataObject::bitmap(MediumKind::CustomOwner, vec![0; 64])
        .with_bytes(CF_DIB.0 as u32, data)
        .into_reader();
    let png = read(reader, registered("PNG"));
    assert_eq!(decode_png(&png), pattern(255));
}

#[test]
fn bitmap_gdi_is_advertised_as_png_and_preserves_every_pixel() {
    let _ole = OleApartment::new();
    let (reader, observations) =
        BitmapDataObject::bitmap(MediumKind::SystemOwned, pattern(0)).into_reader();
    assert!(reader
        .get_formats_for_item_sync(0)
        .unwrap()
        .contains(&"PNG".into()));
    let png = read(reader, registered("PNG"));
    assert_eq!(decode_png(&png), pattern(255));
    assert_eq!(
        *observations.requested.lock().unwrap(),
        [(CF_BITMAP.0, TYMED_GDI.0 as u32)]
    );
    assert!(!bitmap_alive(HBITMAP(
        observations.last_original.load(Ordering::SeqCst)
    )));
}

#[test]
fn bitmap_snapshot_ignores_a_later_global_clipboard_value() {
    static CLIPBOARD: Mutex<()> = Mutex::new(());
    let _serial = CLIPBOARD.lock().unwrap();
    let _ole = OleApartment::new();
    fn assert_clipboard_empty() {
        let object = unsafe { OleGetClipboard() }.unwrap();
        let formats = unsafe { object.EnumFormatEtc(DATADIR_GET.0 as u32) }.unwrap();
        let mut format = [FORMATETC::default()];
        let mut fetched = 0;
        unsafe { formats.Next(&mut format, Some(&mut fetched)) }.unwrap();
        if !format[0].ptd.is_null() {
            unsafe { CoTaskMemFree(Some(format[0].ptd.cast())) };
        }
        assert_eq!(fetched, 0, "This test requires an empty clipboard");
    }
    // OleGetClipboard returns a live proxy, not a snapshot that can safely be restored.
    assert_clipboard_empty();
    let outcome = catch_unwind(AssertUnwindSafe(|| {
        let (reader_a, _) =
            BitmapDataObject::bitmap(MediumKind::CustomOwner, pattern(0)).into_reader();
        let b: IDataObject = BitmapDataObject::bitmap(MediumKind::CustomOwner, vec![0; 64]).into();
        unsafe { OleSetClipboard(&b) }.unwrap();
        let global_b =
            PlatformDataReader::new_with_data_object(unsafe { OleGetClipboard() }.unwrap(), None);
        assert_eq!(
            decode_png(&read(global_b, registered("PNG"))),
            vec![0, 0, 0, 255].repeat(16)
        );
        let png_a = read(reader_a, registered("PNG"));
        assert_eq!(decode_png(&png_a), pattern(255));
    }));
    if let Err(panic) = &outcome {
        eprintln!(
            "Clipboard snapshot assertion failed before cleanup: {}",
            panic
                .downcast_ref::<String>()
                .map(String::as_str)
                .or_else(|| panic.downcast_ref::<&str>().copied())
                .unwrap_or("non-string panic payload")
        );
    }
    unsafe { OleSetClipboard(None::<&IDataObject>) }.expect("Failed to clear the test clipboard");
    assert_clipboard_empty();
    if let Err(panic) = outcome {
        resume_unwind(panic);
    }
}

#[test]
fn bitmap_custom_medium_owner_is_released_once_before_encoding() {
    let _ole = OleApartment::new();
    let (reader, observations) =
        BitmapDataObject::bitmap(MediumKind::CustomOwner, pattern(0)).into_reader();
    let source = reader.snapshot_png_source().unwrap();
    assert_eq!(observations.releases.load(Ordering::SeqCst), 1);
    let copied = match &source {
        PngSource::Bitmap(bitmap) => bitmap.0,
        _ => panic!("Expected bitmap snapshot"),
    };
    let original = HBITMAP(observations.last_original.load(Ordering::SeqCst));
    assert_ne!(copied, original);
    assert!(!bitmap_alive(original));
    assert!(bitmap_alive(copied));
    let png = thread::spawn(move || source.encode().unwrap())
        .join()
        .unwrap();
    assert_eq!(decode_png(&png), pattern(255));
    assert!(!bitmap_alive(copied));
    assert_eq!(observations.releases.load(Ordering::SeqCst), 1);
}

#[test]
fn bitmap_medium_owner_is_released_on_invalid_handle_and_tymed() {
    let _ole = OleApartment::new();
    for kind in [
        MediumKind::NullBitmap,
        MediumKind::InvalidBitmap,
        MediumKind::WrongTymed,
    ] {
        let fixture = BitmapDataObject::bitmap(kind, pattern(0));
        let observations = fixture.observations.clone();
        let object: IDataObject = fixture.into();
        assert!(snapshot_bitmap(&object).is_err());
        assert_eq!(observations.releases.load(Ordering::SeqCst), 1);
    }
}

#[test]
fn bitmap_without_gdi_medium_does_not_advertise_synthetic_png() {
    let _ole = OleApartment::new();
    for medium in [TYMED_HGLOBAL, TYMED_ISTREAM] {
        let mut fixture = BitmapDataObject::bitmap(MediumKind::CustomOwner, pattern(0));
        fixture.formats = vec![make_format_with_tymed(CF_BITMAP.0 as u32, medium)];
        let (reader, observations) = fixture.into_reader();
        assert!(!reader.need_to_synthesize_png().unwrap());
        assert!(!reader
            .get_formats_for_item_sync(0)
            .unwrap()
            .contains(&"PNG".into()));
        assert!(observations.requested.lock().unwrap().is_empty());
    }
}

#[test]
fn bitmap_fallback_keeps_original_png_bytes_and_priority() {
    let _ole = OleApartment::new();
    let png = thread::spawn(|| PngSource::Dib(dib(&pattern(171), true)).encode().unwrap())
        .join()
        .unwrap();
    let format = registered("PNG");
    let (reader, observations) = BitmapDataObject::bitmap(MediumKind::CustomOwner, vec![0; 64])
        .with_bytes(CF_DIBV5.0 as u32, dib(&pattern(42), true))
        .with_bytes(format, png.clone())
        .into_reader();
    assert!(!reader.need_to_synthesize_png().unwrap());
    assert_eq!(read(reader, format), png);
    assert_eq!(
        *observations.requested.lock().unwrap(),
        [(format as u16, (TYMED_HGLOBAL.0 | TYMED_ISTREAM.0) as u32)]
    );
    assert_eq!(observations.releases.load(Ordering::SeqCst), 0);
}

#[test]
fn bitmap_fallback_prefers_dibv5_and_preserves_alpha() {
    let _ole = OleApartment::new();
    let (reader, observations) = BitmapDataObject::bitmap(MediumKind::CustomOwner, vec![0; 64])
        .with_bytes(CF_DIB.0 as u32, dib(&pattern(255), false))
        .with_bytes(CF_DIBV5.0 as u32, dib(&pattern(127), true))
        .into_reader();
    let png = read(reader, registered("PNG"));
    assert_eq!(decode_png(&png), pattern(127));
    assert_eq!(observations.requested.lock().unwrap()[0].0, CF_DIBV5.0);
    assert_eq!(observations.releases.load(Ordering::SeqCst), 0);
}

#[test]
fn bitmap_fallback_prefers_dib_to_gdi() {
    let _ole = OleApartment::new();
    let (reader, observations) = BitmapDataObject::bitmap(MediumKind::CustomOwner, vec![0; 64])
        .with_bytes(CF_DIB.0 as u32, dib(&pattern(255), false))
        .into_reader();
    let png = read(reader, registered("PNG"));
    assert_eq!(decode_png(&png), pattern(255));
    assert_eq!(observations.requested.lock().unwrap()[0].0, CF_DIB.0);
    assert_eq!(observations.releases.load(Ordering::SeqCst), 0);
}

#[test]
fn bitmap_conversion_balances_com_on_the_worker() {
    let _ole = OleApartment::new();
    let (reader, _) = BitmapDataObject::bitmap(MediumKind::CustomOwner, pattern(0)).into_reader();
    let source = reader.snapshot_png_source().unwrap();
    let png = thread::spawn(move || {
        let (mut kind, mut qualifier) = (APTTYPE::default(), APTTYPEQUALIFIER::default());
        assert!(unsafe { CoGetApartmentType(&mut kind, &mut qualifier) }.is_err());
        let png = source.encode().unwrap();
        assert!(unsafe { CoGetApartmentType(&mut kind, &mut qualifier) }.is_err());
        png
    })
    .join()
    .unwrap();
    assert_eq!(decode_png(&png), pattern(255));
}

#[test]
fn bitmap_snapshot_is_released_when_worker_com_initialization_fails() {
    let _ole = OleApartment::new();
    let (mut before, mut before_qualifier) = (APTTYPE::default(), APTTYPEQUALIFIER::default());
    unsafe { CoGetApartmentType(&mut before, &mut before_qualifier) }.unwrap();
    let (reader, observations) =
        BitmapDataObject::bitmap(MediumKind::CustomOwner, pattern(0)).into_reader();
    let source = reader.snapshot_png_source().unwrap();
    let copy = match &source {
        PngSource::Bitmap(bitmap) => bitmap.0,
        _ => panic!("Expected bitmap snapshot"),
    };
    assert!(bitmap_alive(copy));
    assert!(source.encode().is_err());
    assert!(!bitmap_alive(copy));
    assert_eq!(observations.releases.load(Ordering::SeqCst), 1);
    let (mut after, mut after_qualifier) = (APTTYPE::default(), APTTYPEQUALIFIER::default());
    unsafe { CoGetApartmentType(&mut after, &mut after_qualifier) }.unwrap();
    assert_eq!((after, after_qualifier), (before, before_qualifier));
}

#[test]
fn bitmap_advertisement_does_not_change_gif_or_unicode_text_bytes() {
    let _ole = OleApartment::new();
    let gif = registered("GIF");
    let animated = TWO_FRAME_GIF.to_vec();
    let text: Vec<u8> = "שלום test\0"
        .encode_utf16()
        .flat_map(u16::to_le_bytes)
        .collect();
    let (reader, observations) = BitmapDataObject::bitmap(MediumKind::CustomOwner, pattern(0))
        .with_bytes(gif, animated.clone())
        .with_bytes(CF_UNICODETEXT.0 as u32, text.clone())
        .into_reader();
    assert_eq!(read(reader.clone(), gif), animated);
    assert_eq!(
        read(reader, CF_UNICODETEXT.0 as u32),
        text[..text.len() - 2]
    );
    assert_eq!(observations.releases.load(Ordering::SeqCst), 0);
}
