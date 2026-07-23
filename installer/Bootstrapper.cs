using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Security.Cryptography.X509Certificates;
using System.Windows.Forms;

namespace DasaCloudInstaller
{
    internal static class Bootstrapper
    {
        private const string PackageResourceName = "DasaCloud.x64.msix";
        private const string CertificateResourceName = "DasaCloud-Test.cer";

        [STAThread]
        private static int Main()
        {
            var extractionDirectory = Path.Combine(Path.GetTempPath(), "DasaCloud-Setup-" + Guid.NewGuid().ToString("N"));

            try
            {
                Directory.CreateDirectory(extractionDirectory);
                var packagePath = Path.Combine(extractionDirectory, "DasaCloud.x64.msix");
                ExtractResource(PackageResourceName, packagePath, true);

                var certificatePath = Path.Combine(extractionDirectory, "DasaCloud-Test.cer");
                if (ExtractResource(CertificateResourceName, certificatePath, false))
                {
                    TrustCertificate(certificatePath);
                }

                var result = InstallPackage(packagePath);
                if (result.ExitCode != 0)
                {
                    MessageBox.Show(
                        "DasaCloud could not be installed.\r\n\r\n" + result.Error,
                        "DasaCloud Setup",
                        MessageBoxButtons.OK,
                        MessageBoxIcon.Error);
                    return result.ExitCode;
                }

                MessageBox.Show(
                    "DasaCloud was installed successfully.",
                    "DasaCloud Setup",
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Information);
                return 0;
            }
            catch (Exception error)
            {
                MessageBox.Show(
                    "DasaCloud could not be installed.\r\n\r\n" + error.Message,
                    "DasaCloud Setup",
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Error);
                return 1;
            }
            finally
            {
                try
                {
                    if (Directory.Exists(extractionDirectory))
                    {
                        Directory.Delete(extractionDirectory, true);
                    }
                }
                catch
                {
                    // Windows will remove this temporary directory later if it is still in use.
                }
            }
        }

        private static bool ExtractResource(string resourceName, string outputPath, bool required)
        {
            using (var input = Assembly.GetExecutingAssembly().GetManifestResourceStream(resourceName))
            {
                if (input == null)
                {
                    if (required)
                    {
                        throw new InvalidOperationException("The DasaCloud installation package is missing.");
                    }

                    return false;
                }

                using (var output = new FileStream(outputPath, FileMode.Create, FileAccess.Write, FileShare.None))
                {
                    input.CopyTo(output);
                }
            }

            return true;
        }

        private static void TrustCertificate(string certificatePath)
        {
            var certificate = new X509Certificate2(certificatePath);
            using (var store = new X509Store(StoreName.TrustedPeople, StoreLocation.CurrentUser))
            {
                store.Open(OpenFlags.ReadWrite);
                store.Add(certificate);
            }
        }

        private static ProcessResult InstallPackage(string packagePath)
        {
            var escapedPath = packagePath.Replace("'", "''");
            var startInfo = new ProcessStartInfo
            {
                FileName = "powershell.exe",
                Arguments = "-NoProfile -ExecutionPolicy Bypass -Command \"Add-AppxPackage -Path '" + escapedPath + "'\"",
                UseShellExecute = false,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                CreateNoWindow = true
            };

            using (var process = Process.Start(startInfo))
            {
                var output = process.StandardOutput.ReadToEnd();
                var error = process.StandardError.ReadToEnd();
                process.WaitForExit();
                return new ProcessResult(process.ExitCode, string.IsNullOrWhiteSpace(error) ? output : error);
            }
        }

        private sealed class ProcessResult
        {
            internal ProcessResult(int exitCode, string error)
            {
                ExitCode = exitCode;
                Error = error;
            }

            internal int ExitCode { get; private set; }
            internal string Error { get; private set; }
        }
    }
}
