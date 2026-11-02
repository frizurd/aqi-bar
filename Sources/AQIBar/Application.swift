import AQICore
import AppKit

@main
enum AQIBarApplication {
  @MainActor static func main() {
    let app = NSApplication.shared
    let arguments = CommandLine.arguments
    let diagnostic =
      arguments.contains("--check") || arguments.contains("--check-location")
      || arguments.contains("--render-preview")
    let delegate: AppDelegate?
    if diagnostic {
      delegate = nil
      app.setActivationPolicy(.prohibited)
      Task { @MainActor in
        do {
          try await Diagnostics.run(arguments)
          exit(0)
        } catch {
          // Network errors may contain a request URL with the API key.
          let message =
            (error as? AQIError)?.errorDescription ?? (error as? AQIBarError)?.errorDescription
            ?? "Diagnostic failed; check the connection or location."
          fputs("\(message)\n", stderr)
          exit(1)
        }
      }
    } else {
      delegate = AppDelegate()
      app.delegate = delegate
    }
    app.run()
    withExtendedLifetime(delegate) {}
  }
}
