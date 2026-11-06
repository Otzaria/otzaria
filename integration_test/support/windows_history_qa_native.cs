using System;
using System.ComponentModel;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

namespace WinVQa {
    public sealed class VisibleWindow {
        public long handle;
        public uint processId;
        public string title, className;
        public bool visible, sampled;
        public int sampleX, sampleY;
    }
    public static class Native {
        [StructLayout(LayoutKind.Sequential)] public struct Point { public int X; public int Y; }
        [StructLayout(LayoutKind.Sequential)] struct MouseInput {
            public int dx, dy; public uint mouseData, flags, time; public UIntPtr extraInfo;
        }
        [StructLayout(LayoutKind.Sequential)] struct KeyboardInput {
            public ushort key, scan; public uint flags, time; public UIntPtr extraInfo;
        }
        [StructLayout(LayoutKind.Explicit)] struct InputUnion {
            [FieldOffset(0)] public MouseInput mouse;
            [FieldOffset(0)] public KeyboardInput keyboard;
        }
        [StructLayout(LayoutKind.Sequential)] struct Input { public uint type; public InputUnion data; }

        [DllImport("user32.dll", SetLastError = true)] static extern uint SendInput(uint count, Input[] inputs, int size);
        [DllImport("user32.dll")] static extern IntPtr GetKeyboardLayout(uint thread);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern uint MapVirtualKeyEx(uint key, uint mapType, IntPtr layout);
        [DllImport("user32.dll")] public static extern short GetAsyncKeyState(int key);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern IntPtr FindWindowEx(IntPtr parent, IntPtr after, string className, string title);
        [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
        [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
        [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr window);
        [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr window, int command);
        [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr window, out uint process);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowText(IntPtr window, StringBuilder text, int length);
        [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr window, uint message, IntPtr wParam, IntPtr lParam);
        [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
        [DllImport("user32.dll")] public static extern bool GetCursorPos(out Point point);
        delegate bool EnumWindowProc(IntPtr window, IntPtr parameter);
        [DllImport("user32.dll")] static extern bool EnumWindows(EnumWindowProc callback, IntPtr parameter);
        [DllImport("user32.dll")] static extern IntPtr WindowFromPoint(Point point);
        [DllImport("user32.dll")] static extern IntPtr GetAncestor(IntPtr window, uint flags);
        [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr window);
        [DllImport("user32.dll")] static extern int GetSystemMetrics(int index);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetClassName(IntPtr window, StringBuilder name, int length);
        [DllImport("user32.dll", SetLastError = true)] static extern bool OpenClipboard(IntPtr owner);
        [DllImport("user32.dll", SetLastError = true)] static extern bool EmptyClipboard();
        [DllImport("user32.dll")] static extern bool CloseClipboard();
        [DllImport("user32.dll", SetLastError = true)] static extern IntPtr SetClipboardData(uint format, IntPtr memory);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern uint RegisterClipboardFormat(string name);
        [DllImport("kernel32.dll", SetLastError = true)] static extern IntPtr GlobalAlloc(uint flags, UIntPtr bytes);
        [DllImport("kernel32.dll", SetLastError = true)] static extern IntPtr GlobalLock(IntPtr memory);
        [DllImport("kernel32.dll")] static extern bool GlobalUnlock(IntPtr memory);
        [DllImport("kernel32.dll")] static extern IntPtr GlobalFree(IntPtr memory);

        static void ObserveWindow(Dictionary<long, VisibleWindow> windows, IntPtr window, bool sampled, int x, int y) {
            if (window == IntPtr.Zero) return;
            VisibleWindow found;
            if (!windows.TryGetValue(window.ToInt64(), out found)) {
                uint process; GetWindowThreadProcessId(window, out process);
                var title = new StringBuilder(512); var name = new StringBuilder(256);
                GetWindowText(window, title, title.Capacity); GetClassName(window, name, name.Capacity);
                found = new VisibleWindow { handle = window.ToInt64(), processId = process, title = title.ToString(),
                    className = name.ToString(), visible = IsWindowVisible(window) };
                windows.Add(found.handle, found);
            }
            if (sampled) { found.sampled = true; found.sampleX = x; found.sampleY = y; }
        }
        public static VisibleWindow[] ObserveDesktopWindows() {
            var windows = new Dictionary<long, VisibleWindow>();
            EnumWindows((window, data) => { ObserveWindow(windows, window, false, 0, 0); return true; }, IntPtr.Zero);
            ObserveWindow(windows, GetForegroundWindow(), false, 0, 0);
            int left = GetSystemMetrics(76), top = GetSystemMetrics(77), width = GetSystemMetrics(78), height = GetSystemMetrics(79);
            if (width <= 0 || height <= 0 || width > 8192 || height > 8192) throw new Exception("Unexpected desktop bounds for window observation");
            for (int y = top + 32; y < top + height; y += 64) {
                for (int x = left + 32; x < left + width; x += 64) {
                    IntPtr hit = WindowFromPoint(new Point { X = x, Y = y });
                    ObserveWindow(windows, hit, true, x, y);
                    ObserveWindow(windows, GetAncestor(hit, 2), true, x, y);
                }
            }
            var result = new VisibleWindow[windows.Count]; windows.Values.CopyTo(result, 0); return result;
        }
        public static bool WindowStillOwned(IntPtr window, uint expectedPid) {
            uint process; GetWindowThreadProcessId(window, out process);
            return process == expectedPid && IsWindowVisible(window);
        }
        public static bool PointStillOwned(int x, int y, uint expectedPid) {
            IntPtr window = WindowFromPoint(new Point { X = x, Y = y });
            uint process; GetWindowThreadProcessId(window, out process);
            return window != IntPtr.Zero && process == expectedPid && IsWindowVisible(window);
        }
        static Input Key(ushort key, bool up) {
            Input input = new Input { type = 1 };
            input.data.keyboard.key = key;
            input.data.keyboard.flags = (up ? 2u : 0u) | (key == 0x5B ? 1u : 0u);
            return input;
        }
        static void Send(Input[] inputs) {
            uint sent = SendInput((uint)inputs.Length, inputs, Marshal.SizeOf(typeof(Input)));
            if (sent != inputs.Length) throw new Win32Exception(Marshal.GetLastWin32Error(), "SendInput accepted " + sent + "/" + inputs.Length);
        }
        static Input PhysicalKey(ushort key, bool up) {
            uint scan = MapVirtualKeyEx(key, 4, GetKeyboardLayout(0));
            if ((scan & 0xFF) == 0) throw new Exception("No scan code for the requested physical key");
            Input input = Key(key, up);
            input.data.keyboard.scan = (ushort)(scan & 0xFF);
            input.data.keyboard.flags = (up ? 2u : 0u) | ((scan & 0xFF00) == 0xE000 ? 1u : 0u);
            return input;
        }
        public static void OpenHistory() {
            try { Send(new[] { PhysicalKey(0x5B, false), PhysicalKey(0x56, false), PhysicalKey(0x56, true), PhysicalKey(0x5B, true) }); }
            catch { ReleaseKeys(); throw; }
        }
        public static void ReleaseKeys() { Send(new[] { Key(0x56, true), Key(0x5B, true) }); }
        public static void Escape() { Send(new[] { Key(0x1B, false), Key(0x1B, true) }); }
        public static void Click(int x, int y, uint expectedPid) {
            if (!PointStillOwned(x, y, expectedPid)) throw new Exception("The observed Shell target no longer owns this point");
            if (!SetCursorPos(x, y)) throw new Win32Exception(Marshal.GetLastWin32Error());
            if (!PointStillOwned(x, y, expectedPid)) throw new Exception("The observed Shell target moved before its click");
            Input down = new Input(), up = new Input();
            down.data.mouse.flags = 2; up.data.mouse.flags = 4;
            try { Send(new[] { down, up }); } finally { Send(new[] { up }); }
        }
        static void SetBytes(uint format, byte[] bytes) {
            if (format == 0) throw new Win32Exception(Marshal.GetLastWin32Error(), "Clipboard format unavailable");
            IntPtr memory = GlobalAlloc(2, (UIntPtr)bytes.Length);
            if (memory == IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error());
            try {
                IntPtr target = GlobalLock(memory);
                if (target == IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error());
                try { Marshal.Copy(bytes, 0, target, bytes.Length); } finally { GlobalUnlock(memory); }
                if (SetClipboardData(format, memory) == IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error());
                memory = IntPtr.Zero;
            } finally { if (memory != IntPtr.Zero) GlobalFree(memory); }
        }
        public static void PostUnmodifiedV(IntPtr flutterWindow) {
            IntPtr view = FindWindowEx(flutterWindow, IntPtr.Zero, "FLUTTERVIEW", null);
            if (view == IntPtr.Zero) throw new Exception("Flutter view HWND was not found");
            if (!PostMessage(view, 0x0100, new IntPtr(0x56), new IntPtr(1)) ||
                !PostMessage(view, 0x0101, new IntPtr(0x56), new IntPtr(0xC0000001L))) {
                throw new Win32Exception(Marshal.GetLastWin32Error());
            }
        }
        public static void TypeV(bool alt) {
            try {
                Send(alt
                    ? new[] { PhysicalKey(0x12, false), Key(0x56, false), Key(0x56, true), PhysicalKey(0x12, true) }
                    : new[] { Key(0x56, false), Key(0x56, true) });
            } catch {
                if (alt) Send(new[] { Key(0x12, true) });
                ReleaseKeys();
                throw;
            }
        }
        public static void SetFixtureBitmap(IntPtr owner, byte red, byte green, byte blue) {
            byte[] dib = new byte[40 + 4 * 4 * 4];
            Array.Copy(BitConverter.GetBytes(40), 0, dib, 0, 4);
            Array.Copy(BitConverter.GetBytes(4), 0, dib, 4, 4);
            Array.Copy(BitConverter.GetBytes(4), 0, dib, 8, 4);
            Array.Copy(BitConverter.GetBytes((short)1), 0, dib, 12, 2);
            Array.Copy(BitConverter.GetBytes((short)32), 0, dib, 14, 2);
            Array.Copy(BitConverter.GetBytes(64), 0, dib, 20, 4);
            for (int offset = 40; offset < dib.Length; offset += 4) {
                dib[offset] = blue; dib[offset + 1] = green; dib[offset + 2] = red; dib[offset + 3] = 255;
            }
            if (!OpenClipboard(owner)) throw new Win32Exception(Marshal.GetLastWin32Error());
            try {
                if (!EmptyClipboard()) throw new Win32Exception(Marshal.GetLastWin32Error());
                SetBytes(RegisterClipboardFormat("CanUploadToCloudClipboard"), BitConverter.GetBytes(0));
                SetBytes(RegisterClipboardFormat("CanIncludeInClipboardHistory"), BitConverter.GetBytes(1));
                SetBytes(8, dib);
            } finally { CloseClipboard(); }
        }
        public static void SetFixtureText(IntPtr owner, string text) {
            if (!OpenClipboard(owner)) throw new Win32Exception(Marshal.GetLastWin32Error());
            try {
                if (!EmptyClipboard()) throw new Win32Exception(Marshal.GetLastWin32Error());
                // Public per-item formats: request local history, prohibit cloud upload.
                // https://learn.microsoft.com/windows/win32/dataxchg/clipboard-formats
                SetBytes(RegisterClipboardFormat("CanUploadToCloudClipboard"), BitConverter.GetBytes(0));
                SetBytes(RegisterClipboardFormat("CanIncludeInClipboardHistory"), BitConverter.GetBytes(1));
                SetBytes(13, Encoding.Unicode.GetBytes(text + "\0"));
            } finally { CloseClipboard(); }
        }
    }
}
