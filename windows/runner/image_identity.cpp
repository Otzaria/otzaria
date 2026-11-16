#include "image_identity.h"

#include <algorithm>
#include <cstdint>
#include <cstdio>
#include <cstring>

namespace image_identity {

// ה-build-id מ-PT_NOTE של ה-ELF (64 ביט) — מזהה את קובץ הסמלים התואם.
std::string DartBuildId(const MemoryReader& read, ULONG_PTR base) {
  unsigned char header[64] = {};
  if (!read(base, header, sizeof(header)) || header[4] != 2) return "";
  uint64_t phoff = 0;
  uint16_t phentsize = 0, phnum = 0;
  memcpy(&phoff, header + 0x20, sizeof(phoff));
  memcpy(&phentsize, header + 0x36, sizeof(phentsize));
  memcpy(&phnum, header + 0x38, sizeof(phnum));
  if (phentsize < 0x30 || phnum > 64) return "";
  for (uint16_t i = 0; i < phnum; ++i) {
    unsigned char ph[0x30] = {};
    if (!read(base + phoff + i * phentsize, ph, sizeof(ph))) return "";
    uint32_t type = 0;
    uint64_t vaddr = 0, size = 0;
    memcpy(&type, ph, sizeof(type));
    memcpy(&vaddr, ph + 0x10, sizeof(vaddr));
    memcpy(&size, ph + 0x28, sizeof(size));
    if (type != 4 /* PT_NOTE */) continue;
    for (uint64_t at = 0; at + 12 <= size;) {
      uint32_t note[3] = {};  // namesz, descsz, type
      if (!read(base + vaddr + at, note, sizeof(note))) return "";
      const uint64_t name_size = (note[0] + 3) & ~3u;
      const uint64_t desc_size = (note[1] + 3) & ~3u;
      char name[4] = {};
      if (note[2] == 3 /* NT_GNU_BUILD_ID */ && note[0] == 4 && note[1] <= 64 &&
          read(base + vaddr + at + 12, name, sizeof(name)) &&
          memcmp(name, "GNU", 4) == 0) {
        unsigned char id[64] = {};
        if (!read(base + vaddr + at + 12 + name_size, id, note[1])) {
          return "";
        }
        std::string hex;
        char byte[3];
        for (uint32_t b = 0; b < note[1]; ++b) {
          snprintf(byte, sizeof(byte), "%02x", id[b]);
          hex += byte;
        }
        return hex;
      }
      at += 12 + name_size + desc_size;
    }
  }
  return "";
}

// "<pdb> <GUID><age>" מרשומת CodeView RSDS — המפתח בשרת הסמלים של Microsoft,
// שבלעדיו אין PDB לפריים ב-DLL של המערכת.
std::string ModulePdbKey(const MemoryReader& read, ULONG_PTR base) {
  IMAGE_DOS_HEADER dos = {};
  if (!read(base, &dos, sizeof(dos)) || dos.e_magic != IMAGE_DOS_SIGNATURE ||
      dos.e_lfanew <= 0 || dos.e_lfanew > 0x10000) {
    return "";
  }
  IMAGE_NT_HEADERS nt = {};
  if (!read(base + dos.e_lfanew, &nt, sizeof(nt)) ||
      nt.Signature != IMAGE_NT_SIGNATURE ||
      nt.OptionalHeader.Magic != IMAGE_NT_OPTIONAL_HDR_MAGIC ||
      nt.OptionalHeader.NumberOfRvaAndSizes <= IMAGE_DIRECTORY_ENTRY_DEBUG) {
    return "";
  }
  const DWORD image_size = nt.OptionalHeader.SizeOfImage;
  const IMAGE_DATA_DIRECTORY dir =
      nt.OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_DEBUG];
  if (dir.VirtualAddress == 0 || dir.VirtualAddress >= image_size ||
      dir.Size > image_size - dir.VirtualAddress) {
    return "";
  }
  const DWORD count = (std::min)(
      static_cast<DWORD>(dir.Size / sizeof(IMAGE_DEBUG_DIRECTORY)), DWORD{32});
  for (DWORD i = 0; i < count; ++i) {
    IMAGE_DEBUG_DIRECTORY entry = {};
    if (!read(base + dir.VirtualAddress + i * sizeof(entry), &entry,
                   sizeof(entry))) {
      return "";
    }
    if (entry.Type != IMAGE_DEBUG_TYPE_CODEVIEW || entry.AddressOfRawData == 0 ||
        entry.SizeOfData < 25 || entry.SizeOfData > 1024 ||
        entry.AddressOfRawData >= image_size ||
        entry.SizeOfData > image_size - entry.AddressOfRawData) {
      continue;
    }
    // RSDS: חתימה, GUID, age, ונתיב ה-PDB מסתיים ב-0.
    unsigned char data[1024] = {};
    if (!read(base + entry.AddressOfRawData, data, entry.SizeOfData) ||
        memcmp(data, "RSDS", 4) != 0) {
      continue;
    }
    GUID guid = {};
    DWORD age = 0;
    memcpy(&guid, data + 4, sizeof(guid));
    memcpy(&age, data + 20, sizeof(age));
    const char* path = reinterpret_cast<const char*>(data + 24);
    const size_t path_len = strnlen(path, entry.SizeOfData - 24);
    if (path_len == 0 || path_len == entry.SizeOfData - 24) continue;
    std::string pdb(path, path_len);
    const size_t slash = pdb.find_last_of("\\/");
    if (slash != std::string::npos) pdb = pdb.substr(slash + 1);
    if (pdb.empty() || pdb.find(' ') != std::string::npos) continue;
    char key[64];
    snprintf(key, sizeof(key),
             "%08lX%04X%04X%02X%02X%02X%02X%02X%02X%02X%02X%lX", guid.Data1,
             guid.Data2, guid.Data3, guid.Data4[0], guid.Data4[1],
             guid.Data4[2], guid.Data4[3], guid.Data4[4], guid.Data4[5],
             guid.Data4[6], guid.Data4[7], age);
    return pdb + " " + key;
  }
  return "";
}

}  // namespace image_identity
