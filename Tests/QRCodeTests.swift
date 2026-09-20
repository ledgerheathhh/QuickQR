import AppKit
import Vision

@main
enum QRCodeTests {
    static func main() throws {
        let samples = [
            "https://example.com/path?name=hello&value=123#section",
            "你好，世界！这是轻码。",
            "二维码 👋🌈🚀 café",
            "第一行\n第二行\n  保留首尾空格  ",
            "  https://example.com/  ",
            "a",
            String(repeating: "a", count: QRCode.maximumBytes)
        ]
        for (index, text) in samples.enumerated() {
            let result = try QRCode.generate(text)
            let request = VNDetectBarcodesRequest()
            request.symbologies = [.qr]
            try VNImageRequestHandler(cgImage: result.cgImage).perform([request])
            guard request.results?.first?.payloadStringValue == text else {
                fatalError("Round-trip failed for sample \(index)")
            }
            guard NSBitmapImageRep(data: result.png)?.pixelsWide == result.cgImage.width else {
                fatalError("PNG encoding failed")
            }
            print("PASS: round-trip sample \(index + 1), \(text.utf8.count) bytes, \(result.cgImage.width) px")
        }
        for input in ["", " \n\t", String(repeating: "a", count: QRCode.maximumBytes + 1), String(repeating: "中", count: 667)] {
            do {
                _ = try QRCode.generate(input)
                fatalError("Invalid input accepted")
            } catch is QRCode.Failure {
                print("PASS: rejected empty/oversized input (\(input.utf8.count) bytes)")
            }
        }
        print("All 11 checks passed.")
    }
}
