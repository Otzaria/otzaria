using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;

namespace InstalledPluginProbe {
    public sealed class ControlledLogWriter : StreamWriter {
        public ControlledLogWriter(Stream stream) : base(stream) { }
        public override void WriteLine(string value) { throw new IOException("controlled raw writer failure"); }
    }

    public sealed class ControlledRunnerObserver : IDisposable {
        public int Port { get { return 12345; } }
        public DateTime ArmedAtUtc { get; set; } = DateTime.UtcNow;
        public string Snapshot;
        public int Disposals;
        public string SnapshotJson() { return Snapshot; }
        public void Dispose() { Disposals++; }
    }

    public sealed class ControlledProcessFactory : IProcessFactory {
        public string Executable;
        public long Creation;
        public string Mode = "pass";
        public uint ExitStatus = 37;
        public int Opens;
        public int Reads;
        public int Waits;
        public int ExitReads;
        public int Disposals;
        public ManualResetEventSlim IdentityEntered;
        public ManualResetEventSlim ReleaseIdentity;
        public IRetainedProcess Open(uint pid) {
            Opens++;
            if (Mode == "open-error") throw new IOException("controlled open failure");
            return new ControlledProcess(this, pid);
        }
        private sealed class ControlledProcess : IRetainedProcess {
            private readonly ControlledProcessFactory owner;
            private readonly uint pid;
            private readonly long nativeCreation;
            public ControlledProcess(ControlledProcessFactory owner, uint pid) {
                this.owner = owner; this.pid = pid; nativeCreation = owner.Creation;
            }
            public ProcessIdentity ReadIdentity() {
                owner.Reads++;
                if (owner.Mode == "delayed-identity") {
                    owner.IdentityEntered.Set();
                    if (!owner.ReleaseIdentity.Wait(10000)) throw new TimeoutException("controlled native identity deadline");
                }
                if (owner.Mode == "identity-error") throw new IOException("controlled identity failure");
                return new ProcessIdentity {
                    Pid = owner.Mode == "native-pid" ? pid + 1 : pid,
                    CreationFileTime = nativeCreation + (owner.Mode == "native-creation" ? 1 : 0),
                    Executable = owner.Mode == "native-executable" ? owner.Executable + ".foreign" : owner.Executable
                };
            }
            public uint Wait(uint milliseconds) {
                owner.Waits++;
                if (owner.Mode == "wait-error" || (owner.Mode == "post-wait-error" && milliseconds != 0)) throw new IOException("controlled native wait failure");
                if (milliseconds == 0) return owner.Mode == "exited-before-ack" ? 0u : 258u;
                return owner.Mode == "still-running" ? 258u : 0u;
            }
            public ProcessExit ReadExit() {
                owner.ExitReads++;
                if (owner.Mode == "exit-error") throw new IOException("controlled exit query failure");
                return new ProcessExit {
                    CreationFileTime = nativeCreation + (owner.Mode == "exit-creation" ? 1 : 0),
                    ExitFileTime = owner.Mode == "exit-before-bootstrap" ? nativeCreation : DateTime.UtcNow.ToFileTimeUtc(),
                    Status = owner.ExitStatus
                };
            }
            public void Dispose() {
                owner.Disposals++;
                if (owner.Mode == "close-error") throw new IOException("controlled close failure");
            }
        }
    }

    public static class LifetimeObserverControls {
        private static int assertions;
        private static void Check(bool condition, string message) {
            assertions++;
            if (!condition) throw new Exception(message);
        }
        private static async Task<byte[]> Exchange(int port, byte[] bytes) {
            using (var timeout = new CancellationTokenSource(3000))
            using (var client = new TcpClient()) {
                await client.ConnectAsync(IPAddress.Loopback, port, timeout.Token).ConfigureAwait(false);
                var stream = client.GetStream();
                await stream.WriteAsync(bytes, timeout.Token).ConfigureAwait(false);
                client.Client.Shutdown(SocketShutdown.Send);
                return await LifetimeObserver.ReadBoundedAsync(stream, timeout.Token).ConfigureAwait(false);
            }
        }

        public static string Run() { return RunAsync().GetAwaiter().GetResult(); }
        private static async Task<string> RunAsync() {
            assertions = 0;
            var outcomes = new List<object>();
            var modes = new[] { "pass", "nonce", "campaign", "run-pid", "stale-bootstrap", "future-bootstrap", "stale-creation",
                "open-error", "identity-error", "native-pid", "native-creation", "native-executable", "exited-before-ack",
                "wait-error", "post-wait-error", "still-running", "exit-error", "exit-creation", "exit-before-bootstrap", "close-error",
                "oversized", "duplicate-field", "duplicate-message", "missing-field", "fractional-pid", "unsigned-exit", "pid-reused-after-ack", "no-client" };
            foreach (string mode in modes) {
                string path = Path.GetFullPath("controlled-process.exe");
                string campaign = Guid.NewGuid().ToString("N");
                string token = new string('a', 64);
                var factory = new ControlledProcessFactory { Executable = path, Mode = mode, ExitStatus = mode == "unsigned-exit" ? 0xC0000005u : 37u };
                using (var observer = new LifetimeObserver(path, campaign, token, 3000, factory)) {
                    factory.Creation = observer.ArmedAtUtc.ToFileTimeUtc() + 1;
                    long micros = (DateTime.UtcNow.Ticks - DateTime.UnixEpoch.Ticks) / 10;
                    var hello = new Dictionary<string, object> {
                        { "version", 1 }, { "kind", "hello" }, { "campaignId", mode == "campaign" ? new string('f', 32) : campaign },
                        { "token", mode == "nonce" ? new string('b', 64) : token }, { "pid", 42 },
                        { "runId", (mode == "run-pid" ? "43-" : "42-") + micros.ToString(CultureInfo.InvariantCulture) },
                        { "creationFileTime", factory.Creation.ToString(CultureInfo.InvariantCulture) }
                    };
                    if (mode == "stale-bootstrap") hello["runId"] = "42-" + ((observer.ArmedAtUtc.AddSeconds(-1).Ticks - DateTime.UnixEpoch.Ticks) / 10);
                    if (mode == "future-bootstrap") hello["runId"] = "42-" + ((DateTime.UtcNow.AddMinutes(1).Ticks - DateTime.UnixEpoch.Ticks) / 10);
                    if (mode == "stale-creation") hello["creationFileTime"] = (factory.Creation - TimeSpan.TicksPerSecond).ToString(CultureInfo.InvariantCulture);
                    if (mode == "missing-field") hello.Remove("creationFileTime");
                    if (mode == "fractional-pid") hello["pid"] = 42.5;
                    var json = JsonSerializer.Serialize(hello);
                    if (mode == "oversized") json += new string(' ', 4097);
                    if (mode == "duplicate-field") json = json.Insert(1, "\"pid\":42,");
                    if (mode == "duplicate-message") json += json;
                    byte[] reply = null;
                    if (mode != "no-client") {
                        try { reply = await Exchange(observer.Port, Encoding.UTF8.GetBytes(json)).ConfigureAwait(false); }
                        catch (Exception) { }
                    }
                    bool shouldAcknowledge = mode == "pass" || mode == "still-running" || mode == "exit-error" ||
                        mode == "exit-creation" || mode == "exit-before-bootstrap" || mode == "close-error" || mode == "unsigned-exit" || mode == "post-wait-error" || mode == "pid-reused-after-ack";
                    Check((reply != null) == shouldAcknowledge, mode + ": acknowledgement must match identity validation");
                    if (shouldAcknowledge) {
                        using (var ack = JsonDocument.Parse(reply)) {
                            Check(ack.RootElement.GetProperty("creationFileTime").GetString() == hello["creationFileTime"].ToString(), mode + ": exact FILETIME ack");
                            Check(ack.RootElement.GetProperty("runId").GetString() == hello["runId"].ToString(), mode + ": exact run ack");
                            Check(ack.RootElement.GetProperty("bootstrapQuiescent").GetBoolean(), mode + ": quiescent acknowledgement");
                        }
                        int reads = factory.Reads, waits = factory.Waits;
                        await Task.Delay(20).ConfigureAwait(false);
                        Check(factory.Reads == reads && factory.Waits == waits && factory.ExitReads == 0, mode + ": no native polling between ack and post-driver collection");
                        using (var duplicate = new TcpClient()) {
                            bool rejected = false;
                            try { await duplicate.ConnectAsync(IPAddress.Loopback, observer.Port).ConfigureAwait(false); }
                            catch (SocketException) { rejected = true; }
                            Check(rejected, mode + ": listener closes before acknowledgement");
                        }
                    }
                    if (mode == "pid-reused-after-ack") factory.Creation += TimeSpan.TicksPerSecond;
                    observer.Complete(25);
                    using (var evidence = JsonDocument.Parse(observer.SnapshotJson())) {
                        var root = evidence.RootElement;
                        bool success = mode == "pass" || mode == "unsigned-exit" || mode == "pid-reused-after-ack";
                        Check(root.GetProperty("availability").GetString() == (success ? "collected" : "unavailable"), mode + ": evidence result");
                        var cleanup = root.GetProperty("cleanup");
                        Check(cleanup.GetProperty("listenerStopped").GetBoolean() && cleanup.GetProperty("channelClosed").GetBoolean() && cleanup.GetProperty("bootstrapTaskCompleted").GetBoolean(), mode + ": endpoint and bootstrap task cleanup");
                        if (success) {
                            Check(root.GetProperty("exitStatus").GetUInt32() == factory.ExitStatus, mode + ": actual unsigned exit status");
                            Check(factory.Opens == 1 && factory.Reads == 1 && factory.Waits == 2 && factory.ExitReads == 1 && factory.Disposals == 1, mode + ": exactly one retained native identity and exit read");
                        } else {
                            Check(root.GetProperty("errors").GetArrayLength() > 0, mode + ": failure evidence retained");
                            if (mode != "close-error") Check(root.GetProperty("exitStatus").ValueKind == JsonValueKind.Null, mode + ": no invented exit status");
                        }
                        if (factory.Opens == 1 && mode != "open-error") Check(factory.Disposals == 1, mode + ": owned handle disposal attempted");
                        Check(!observer.SnapshotJson().Contains(token), mode + ": authentication secret is not saved");
                        outcomes.Add(new { mode, availability = root.GetProperty("availability").GetString() });
                    }
                }
            }
            using (var entered = new ManualResetEventSlim())
            using (var release = new ManualResetEventSlim()) {
                string path = Path.GetFullPath("controlled-process.exe");
                string campaign = Guid.NewGuid().ToString("N"), token = new string('a', 64);
                var factory = new ControlledProcessFactory {
                    Executable = path, Mode = "delayed-identity", IdentityEntered = entered, ReleaseIdentity = release
                };
                using (var observer = new LifetimeObserver(path, campaign, token, 30000, factory)) {
                    factory.Creation = observer.ArmedAtUtc.ToFileTimeUtc() + 1;
                    long micros = (DateTime.UtcNow.Ticks - DateTime.UnixEpoch.Ticks) / 10;
                    var request = JsonSerializer.SerializeToUtf8Bytes(new Dictionary<string, object> {
                        { "version", 1 }, { "kind", "hello" }, { "campaignId", campaign }, { "token", token },
                        { "pid", 42 }, { "runId", "42-" + micros.ToString(CultureInfo.InvariantCulture) },
                        { "creationFileTime", factory.Creation.ToString(CultureInfo.InvariantCulture) }
                    });
                    var exchange = Exchange(observer.Port, request);
                    try {
                        Check(entered.Wait(3000), "delayed native call was reached");
                        observer.Complete(25);
                        using (var partial = JsonDocument.Parse(observer.SnapshotJson())) {
                            Check(partial.RootElement.GetProperty("availability").GetString() == "unavailable", "late bootstrap cannot report success");
                            Check(!partial.RootElement.GetProperty("cleanup").GetProperty("handleClosed").GetBoolean(), "pending cleanup is reported honestly");
                        }
                    } finally { release.Set(); }
                    try { await exchange.ConfigureAwait(false); } catch (Exception) { }
                    var deadline = DateTime.UtcNow.AddSeconds(3);
                    bool lateCleanup = false;
                    while (DateTime.UtcNow < deadline) {
                        await Task.Delay(20).ConfigureAwait(false);
                        using (var snapshot = JsonDocument.Parse(observer.SnapshotJson())) {
                            lateCleanup = snapshot.RootElement.GetProperty("cleanup").TryGetProperty("lateBootstrapCleanupAtUtc", out _);
                        }
                        if (lateCleanup) break;
                    }
                    Check(lateCleanup && factory.Disposals == 1, "the late task releases its exact owned handle once");
                    using (var evidence = JsonDocument.Parse(observer.SnapshotJson())) {
                        var root = evidence.RootElement;
                        Check(root.GetProperty("availability").GetString() == "unavailable", "late cleanup does not upgrade a failed run");
                        Check(root.GetProperty("exitStatus").ValueKind == JsonValueKind.Null, "late bootstrap cannot invent an exit");
                        Check(root.GetProperty("cleanup").GetProperty("bootstrapTaskCompleted").GetBoolean(), "late bootstrap task drained");
                    }
                    outcomes.Add(new { mode = "delayed-identity", availability = "unavailable" });
                }
            }
            return JsonSerializer.Serialize(new { assertions, outcomes, scope = "Real loopback protocol with controlled native process API; native Windows is separate." });
        }
    }
}
