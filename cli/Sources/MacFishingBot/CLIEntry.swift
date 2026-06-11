import Foundation

@main
struct MacFishingBotCLI {
    static func main() {
        do {
            try MacFishingBot().run(arguments: Array(CommandLine.arguments.dropFirst()))
        } catch {
            print("error: \(error)")
            exit(1)
        }
    }
}
