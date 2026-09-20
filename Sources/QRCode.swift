import AppKit
import CoreImage

enum QRCode {
    static let maximumBytes = 2_000
    private static let context = CIContext(options: [.useSoftwareRenderer: true])

    enum Failure: LocalizedError {
        case empty, tooLong, generation

        var errorDescription: String? {
            switch self {
            case .empty: return "输入文字或链接，即可生成二维码"
            case .tooLong: return "内容过长，请缩短到 2,000 个 UTF-8 字节以内"
            case .generation: return "这段内容暂时无法生成二维码，请缩短后重试"
            }
        }
    }

    struct Result {
        let cgImage: CGImage
        let png: Data
        var image: NSImage {
            NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        }
    }

    static func generate(_ text: String) throws -> Result {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw Failure.empty }
        let data = Data(text.utf8)
        guard data.count <= maximumBytes else { throw Failure.tooLong }
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { throw Failure.generation }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let code = filter.outputImage else { throw Failure.generation }

        // Four white modules on every side are required for reliable scanning.
        let bounds = code.extent.insetBy(dx: -4, dy: -4)
        let white = CIImage(color: CIColor(red: 1, green: 1, blue: 1)).cropped(to: bounds)
        let scale = max(4, floor(1024 / bounds.width))
        let output = code.composited(over: white)
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cgImage = context.createCGImage(output, from: output.extent),
              let png = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:])
        else { throw Failure.generation }
        return Result(cgImage: cgImage, png: png)
    }
}
