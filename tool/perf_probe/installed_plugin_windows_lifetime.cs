using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Globalization;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.Win32.SafeHandles;

namespace InstalledPluginProbe {
    public sealed class ProcessIdentity {
        public uint Pid { get; set; }
        public long CreationFileTime { get; set; }
        public string Executable { get; set; }
    }

    public sealed class ProcessExit {
        public long CreationFileTime { get; set; }
        public long ExitFileTime { get; set; }
        public uint Status { get; set; }
    }

    public interface IRetainedProcess : IDisposable {
        ProcessIdentity ReadIdentity();
        uint Wait(uint milliseconds);
        ProcessExit ReadExit();
    }

    public interface IProcessFactory {
        IRetainedProcess Open(uint pid);
    }

    public sealed class WindowsProcessFactory : IProcessFactory {
        public IRetainedProcess Open(uint pid) { return new WindowsProcess(pid); }
    }

    internal sealed class NativeProcessHandle : SafeHandleZeroOrMinusOneIsInvalid {
        internal bool Released;
        internal int ReleaseError;
        public NativeProcessHandle() : base(true) { }
        protected override bool ReleaseHandle() {
            Released = CloseHandle(handle);
            if (!Released) ReleaseError = Marshal.GetLastWin32Error();
            return Released;
        }
        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool CloseHandle(IntPtr handle);
    }

    public sealed class WindowsProcess : IRetainedProcess {
        private readonly NativeProcessHandle handle;
        public WindowsProcess(uint pid) {
            if (!RuntimeInformation.IsOSPlatform(OSPlatform.Windows))
                throw new PlatformNotSupportedException("Native process handles require Windows.");
            handle = OpenProcess(0x00100000 | 0x00001000, false, pid);
            if (handle.IsInvalid) {
                var error = new Win32Exception(Marshal.GetLastWin32Error(), "OpenProcess");
                handle.Dispose();
                throw error;
            }
        }

        public ProcessIdentity ReadIdentity() {
            uint pid = GetProcessId(handle);
            if (pid == 0) throw new Win32Exception(Marshal.GetLastWin32Error(), "GetProcessId");
            long creation, exit, kernel, user;
            if (!GetProcessTimes(handle, out creation, out exit, out kernel, out user))
                throw new Win32Exception(Marshal.GetLastWin32Error(), "GetProcessTimes(identity)");
            var path = new StringBuilder(32768);
            uint length = (uint)path.Capacity;
            if (!QueryFullProcessImageName(handle, 0, path, ref length))
                throw new Win32Exception(Marshal.GetLastWin32Error(), "QueryFullProcessImageNameW");
            return new ProcessIdentity { Pid = pid, CreationFileTime = creation, Executable = path.ToString() };
        }

        public uint Wait(uint milliseconds) {
            uint result = WaitForSingleObject(handle, milliseconds);
            if (result == UInt32.MaxValue)
                throw new Win32Exception(Marshal.GetLastWin32Error(), "WaitForSingleObject");
            return result;
        }

        public ProcessExit ReadExit() {
            uint status;
            long creation, exit, kernel, user;
            if (!GetExitCodeProcess(handle, out status))
                throw new Win32Exception(Marshal.GetLastWin32Error(), "GetExitCodeProcess");
            if (!GetProcessTimes(handle, out creation, out exit, out kernel, out user))
                throw new Win32Exception(Marshal.GetLastWin32Error(), "GetProcessTimes(exit)");
            return new ProcessExit { CreationFileTime = creation, ExitFileTime = exit, Status = status };
        }

        public void Dispose() {
            handle.Dispose();
            if (!handle.Released) throw new Win32Exception(handle.ReleaseError, "CloseHandle");
        }

        public static ProcessIdentity CurrentIdentity() {
            if (!RuntimeInformation.IsOSPlatform(OSPlatform.Windows))
                throw new PlatformNotSupportedException("Native process creation time requires Windows.");
            long creation, exit, kernel, user;
            if (!GetProcessTimes(GetCurrentProcess(), out creation, out exit, out kernel, out user))
                throw new Win32Exception(Marshal.GetLastWin32Error(), "GetProcessTimes(current process)");
            return new ProcessIdentity { Pid = (uint)Environment.ProcessId, CreationFileTime = creation };
        }

        [DllImport("kernel32.dll")]
        private static extern IntPtr GetCurrentProcess();
        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool GetProcessTimes(IntPtr process, out long creation, out long exit, out long kernel, out long user);
        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern NativeProcessHandle OpenProcess(uint access, [MarshalAs(UnmanagedType.Bool)] bool inherit, uint pid);
        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern uint GetProcessId(NativeProcessHandle process);
        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool GetProcessTimes(NativeProcessHandle process, out long creation, out long exit, out long kernel, out long user);
        [DllImport("kernel32.dll", EntryPoint = "QueryFullProcessImageNameW", CharSet = CharSet.Unicode, ExactSpelling = true, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool QueryFullProcessImageName(NativeProcessHandle process, uint flags, StringBuilder path, ref uint length);
        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern uint WaitForSingleObject(NativeProcessHandle process, uint milliseconds);
        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool GetExitCodeProcess(NativeProcessHandle process, out uint status);
    }

    public sealed class LifetimeObserver : IDisposable {
        private readonly TcpListener listener;
        private readonly CancellationTokenSource cancellation = new CancellationTokenSource();
        private readonly Task bootstrap;
        private readonly IProcessFactory factory;
        private readonly string token;
        private readonly string expectedExecutable;
        private IRetainedProcess process;
        private ProcessIdentity identity;
        private DateTime bootstrapUtc;
        private bool completed;
        private readonly object evidenceGate = new object();
        private readonly List<string> errors = new List<string>();
        private readonly Dictionary<string, object> record;
        private readonly Dictionary<string, object> cleanup = new Dictionary<string, object> {
            { "handleAcquired", false }, { "handleClosed", false }, { "listenerStopped", false },
            { "channelClosed", false }, { "bootstrapTaskCompleted", false }
        };
        public int Port { get; private set; }
        public string CampaignId { get; private set; }
        public DateTime ArmedAtUtc { get; private set; }

        public LifetimeObserver(string executable, string campaign, string authenticationToken, int startupMilliseconds)
            : this(executable, campaign, authenticationToken, startupMilliseconds, new WindowsProcessFactory()) { }

        public LifetimeObserver(string executable, string campaign, string authenticationToken, int startupMilliseconds, IProcessFactory processFactory) {
            if (!Path.IsPathFullyQualified(executable) || !Regex.IsMatch(campaign, "^[a-f0-9]{32}$") ||
                !Regex.IsMatch(authenticationToken, "^[a-f0-9]{64}$") || startupMilliseconds < 100 || startupMilliseconds > 1200000)
                throw new ArgumentException("Invalid lifetime observer configuration.");
            expectedExecutable = Path.GetFullPath(executable);
            CampaignId = campaign;
            token = authenticationToken;
            factory = processFactory ?? throw new ArgumentNullException(nameof(processFactory));
            listener = new TcpListener(IPAddress.Loopback, 0);
            try {
                listener.Start(1);
                Port = ((IPEndPoint)listener.LocalEndpoint).Port;
                ArmedAtUtc = DateTime.UtcNow;
                record = new Dictionary<string, object> {
                    { "source", "Retained process handle; authenticated bootstrap only" },
                    { "nativeAdapter", factory.GetType().FullName },
                    { "availability", "armed" }, { "armedAtUtc", ArmedAtUtc }, { "finishedAtUtc", null },
                    { "campaignId", campaign }, { "expectedExecutable", expectedExecutable },
                    { "processName", Path.GetFileName(expectedExecutable) }, { "identity", null },
                    { "identityVerified", false },
                    { "bootstrapUtc", null }, { "runId", null }, { "acknowledgedAtUtc", null },
                    { "bootstrapQuiescent", false }, { "waitResult", null }, { "exitStatus", null },
                    { "exitFileTime", null }, { "errors", errors }, { "cleanup", cleanup },
                    { "startupTimeoutMilliseconds", startupMilliseconds }
                };
                cancellation.CancelAfter(startupMilliseconds);
                bootstrap = Task.Run(BootstrapAsync);
            } catch {
                listener.Stop();
                cancellation.Dispose();
                throw;
            }
        }

        private void Error(Exception error) {
            var message = error.GetType().Name + ": " + error.Message;
            lock (evidenceGate) {
                errors.Add(message.Substring(0, Math.Min(2048, message.Length)));
                record["availability"] = "unavailable";
            }
        }

        private void Record(string key, object value) { lock (evidenceGate) record[key] = value; }
        private void Cleanup(string key, object value) { lock (evidenceGate) cleanup[key] = value; }

        private async Task BootstrapAsync() {
            TcpClient client = null;
            bool ready = false;
            try {
                client = await listener.AcceptTcpClientAsync(cancellation.Token).ConfigureAwait(false);
                listener.Stop();
                Cleanup("listenerStopped", true);
                cancellation.CancelAfter(15000);
                var stream = client.GetStream();
                var request = await ReadBoundedAsync(stream, cancellation.Token).ConfigureAwait(false);
                Record("requestBytes", request.Length);
                using (var json = JsonDocument.Parse(request)) {
                    var hello = json.RootElement;
                    RequireKeys(hello, "version", "kind", "campaignId", "token", "pid", "runId", "creationFileTime");
                    if (hello.GetProperty("version").GetInt32() != 1 || hello.GetProperty("kind").GetString() != "hello" ||
                        hello.GetProperty("campaignId").GetString() != CampaignId ||
                        !CryptographicOperations.FixedTimeEquals(Encoding.UTF8.GetBytes(hello.GetProperty("token").GetString() ?? ""), Encoding.UTF8.GetBytes(token)))
                        throw new InvalidDataException("The bootstrap authentication or protocol does not match this launch.");
                    uint pid = hello.GetProperty("pid").GetUInt32();
                    var runId = hello.GetProperty("runId").GetString();
                    var match = Regex.Match(runId ?? "", "^([1-9][0-9]*)-([0-9]{16})$");
                    if (pid == 0 || !match.Success || UInt32.Parse(match.Groups[1].Value, CultureInfo.InvariantCulture) != pid)
                        throw new InvalidDataException("The bootstrap PID and run identity disagree.");
                    bootstrapUtc = DateTime.UnixEpoch.AddTicks(checked(Int64.Parse(match.Groups[2].Value, CultureInfo.InvariantCulture) * 10));
                    long creation = Int64.Parse(hello.GetProperty("creationFileTime").GetString(), CultureInfo.InvariantCulture);
                    if (bootstrapUtc < ArmedAtUtc || bootstrapUtc > DateTime.UtcNow || creation < ArmedAtUtc.ToFileTimeUtc() || creation > bootstrapUtc.ToFileTimeUtc())
                        throw new InvalidDataException("The bootstrap or native creation time is outside this launch.");
                    process = factory.Open(pid);
                    Cleanup("handleAcquired", true);
                    identity = process.ReadIdentity();
                    Record("identity", new Dictionary<string, object> {
                        { "pid", identity.Pid }, { "creationFileTime", identity.CreationFileTime.ToString(CultureInfo.InvariantCulture) },
                        { "executable", identity.Executable }
                    });
                    Record("runId", runId);
                    Record("bootstrapUtc", bootstrapUtc);
                    if (identity.Pid != pid || identity.CreationFileTime != creation ||
                        !String.Equals(Path.GetFullPath(identity.Executable), expectedExecutable, StringComparison.OrdinalIgnoreCase))
                        throw new InvalidDataException("The retained handle does not match the exact PID, executable and native creation time.");
                    if (process.Wait(0) != 258) throw new InvalidDataException("The process exited before bootstrap acknowledgement.");
                    Record("identityVerified", true);
                    cancellation.Token.ThrowIfCancellationRequested();
                    var acknowledged = DateTime.UtcNow;
                    Record("acknowledgedAtUtc", acknowledged);
                    Record("bootstrapQuiescent", true);
                    var reply = JsonSerializer.SerializeToUtf8Bytes(new Dictionary<string, object> {
                        { "version", 1 }, { "kind", "ready" }, { "campaignId", CampaignId }, { "token", token },
                        { "pid", pid }, { "runId", runId }, { "creationFileTime", creation.ToString(CultureInfo.InvariantCulture) },
                        { "executable", identity.Executable }, { "acknowledgedAtUtc", acknowledged }, { "bootstrapQuiescent", true }
                    });
                    if (reply.Length > 4096) throw new InvalidDataException("The bootstrap acknowledgement exceeds 4096 bytes.");
                    await stream.WriteAsync(reply, cancellation.Token).ConfigureAwait(false);
                    ready = true;
                    Record("availability", "ready");
                }
            } catch (Exception error) { Error(error); }
            finally {
                cancellation.CancelAfter(Timeout.Infinite);
                try { listener.Stop(); Cleanup("listenerStopped", true); } catch (Exception error) { Error(error); }
                try { if (client != null) client.Dispose(); Cleanup("channelClosed", true); } catch (Exception error) { Error(error); }
                if (!ready) CloseHandle();
                Cleanup("bootstrapTaskCompleted", true);
            }
        }

        private void CloseHandle() {
            if (process == null || (bool)cleanup["handleClosed"]) return;
            try { process.Dispose(); Cleanup("handleClosed", true); } catch (Exception error) { Error(error); }
        }

        public void Complete(uint exitTimeoutMilliseconds) {
            if (completed) return;
            if (exitTimeoutMilliseconds > 15000) throw new ArgumentOutOfRangeException(nameof(exitTimeoutMilliseconds));
            completed = true;
            cancellation.Cancel();
            if (!bootstrap.Wait(5000)) {
                Error(new TimeoutException("The owned bootstrap task did not drain after cancellation."));
                Record("finishedAtUtc", DateTime.UtcNow);
                // A synchronous native call can outlive the cancellation budget.
                // Its task still owns the handle: release it after that task ends,
                // even if the ready acknowledgement had already been written.
                _ = bootstrap.ContinueWith(_ => {
                    CloseHandle();
                    cancellation.Dispose();
                    Record("availability", "unavailable");
                    Cleanup("lateBootstrapCleanupAtUtc", DateTime.UtcNow);
                }, CancellationToken.None, TaskContinuationOptions.ExecuteSynchronously, TaskScheduler.Default);
                return;
            }
            try {
                if ((string)record["availability"] != "ready") throw new InvalidDataException("No completed bootstrap acknowledgement.");
                uint wait = process.Wait(exitTimeoutMilliseconds);
                Record("waitResult", wait);
                if (wait != 0) throw new TimeoutException("The retained process handle was not signaled within the bounded post-driver wait.");
                var exit = process.ReadExit();
                if (exit.CreationFileTime != identity.CreationFileTime || exit.ExitFileTime <= bootstrapUtc.ToFileTimeUtc() || exit.ExitFileTime > DateTime.UtcNow.ToFileTimeUtc())
                    throw new InvalidDataException("The retained handle exit times do not match the bootstrap lifetime.");
                Record("exitStatus", exit.Status);
                Record("exitFileTime", exit.ExitFileTime.ToString(CultureInfo.InvariantCulture));
                Record("availability", "collected");
            } catch (Exception error) { Error(error); }
            finally {
                CloseHandle();
                cancellation.Dispose();
                Record("finishedAtUtc", DateTime.UtcNow);
            }
        }

        public string SnapshotJson() {
            if (!completed) throw new InvalidOperationException("Collect the observer before serializing its evidence.");
            lock (evidenceGate) return JsonSerializer.Serialize(record);
        }

        public void Dispose() { Complete(0); }

        public static async Task<byte[]> ReadBoundedAsync(Stream stream, CancellationToken cancellation) {
            var bytes = new byte[4097];
            int length = 0;
            while (true) {
                int read = await stream.ReadAsync(bytes.AsMemory(length, bytes.Length - length), cancellation).ConfigureAwait(false);
                if (read == 0) break;
                length += read;
                if (length > 4096) throw new InvalidDataException("The bootstrap message exceeds 4096 bytes.");
            }
            if (length == 0) throw new InvalidDataException("The bootstrap message is empty.");
            return bytes.AsSpan(0, length).ToArray();
        }

        private static void RequireKeys(JsonElement value, params string[] keys) {
            if (value.ValueKind != JsonValueKind.Object) throw new InvalidDataException("A bootstrap JSON object is required.");
            var actual = new HashSet<string>(StringComparer.Ordinal);
            foreach (var property in value.EnumerateObject())
                if (!actual.Add(property.Name)) throw new InvalidDataException("Duplicate bootstrap field.");
            if (!actual.SetEquals(keys)) throw new InvalidDataException("Unexpected or missing bootstrap fields.");
        }
    }
}
