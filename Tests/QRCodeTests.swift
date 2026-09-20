import AppKit
import Vision
import XCTest

final class QRCodeValidationTests: XCTestCase {
    func testAcceptsBoundaryLength() throws {
        let input = String(repeating: "a", count: QRCode.maximumBytes)
        XCTAssertEqual(try QRCode.validate(input).count, QRCode.maximumBytes)
    }

    func testRejectsEmptyInput() {
        for input in ["", " \n\t"] {
            XCTAssertThrowsError(try QRCode.validate(input)) { error in
                XCTAssertEqual(error as? QRCode.Failure, .empty)
            }
        }
    }

    func testRejectsOversizedUTF8Input() {
        for input in [
            String(repeating: "a", count: QRCode.maximumBytes + 1),
            String(repeating: "中", count: 667)
        ] {
            XCTAssertThrowsError(try QRCode.validate(input)) { error in
                XCTAssertEqual(error as? QRCode.Failure, .tooLong)
            }
        }
    }
}

final class QRCodeVisionIntegrationTests: XCTestCase {
    func testRoundTripSamples() throws {
        guard ProcessInfo.processInfo.environment["QUICKQR_RUN_VISION_TESTS"] == "1" else {
            throw XCTSkip("Set QUICKQR_RUN_VISION_TESTS=1 to run Core Image and Vision integration checks")
        }
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
                XCTFail("Round-trip failed for sample \(index)")
                continue
            }
            guard NSBitmapImageRep(data: result.png)?.pixelsWide == result.cgImage.width else {
                XCTFail("PNG encoding failed for sample \(index)")
                continue
            }
        }
    }
}
