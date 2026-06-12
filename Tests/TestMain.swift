import Testing

/// The tests build as a small executable (`swift run NiceShotTests`)
/// rather than a SwiftPM test bundle, because the Command Line Tools'
/// `swiftpm-testing-helper` fails to execute discovered tests (it exits 0
/// without running anything). Calling Swift Testing's entry point directly
/// sidesteps the broken helper and behaves identically everywhere.
@main
struct TestMain {
    static func main() async {
        await __swiftPMEntryPoint() as Never
    }
}
