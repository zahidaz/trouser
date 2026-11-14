import AppKit

@main
@MainActor
struct TrouserApp {
    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard getppid() == 1 else {
            exit(ControlClient.run(arguments))
        }

        FileLimit.raise()
        let app = NSApplication.shared
        let delegate = AppDelegate(launchedFromCLI: ControlPath.consumeLaunchFromCLI())
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.mainMenu = MainMenu.make()
        withExtendedLifetime(delegate) {
            app.run()
        }
    }
}
