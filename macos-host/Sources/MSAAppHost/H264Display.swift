import AVFoundation
import CoreMedia
import Foundation

@MainActor
final class H264Display {
    let layer = AVSampleBufferDisplayLayer()
    private var sps: Data?
    private var pps: Data?
    private var format: CMVideoFormatDescription?

    init() {
        layer.videoGravity = .resizeAspect
        layer.backgroundColor = CGColor(gray: 0.08, alpha: 1)
    }

    func prepareForStreamResize() {
        sps = nil
        pps = nil
        format = nil
        layer.flush()
    }

    func consume(payload: Data, ptsMicroseconds: UInt64, isKeyFrame: Bool) {
        let units = NALUnits.split(payload)
        for unit in units {
            guard let first = unit.first else { continue }
            switch first & 0x1f {
            case 7: if sps != unit { sps = unit; format = nil }
            case 8: if pps != unit { pps = unit; format = nil }
            default: break
            }
        }
        if format == nil { format = makeFormat() }
        guard let format else { return }
        let pictures = units.filter {
            guard let first = $0.first else { return false }
            let type = first & 0x1f
            return type != 7 && type != 8 && type != 9
        }
        guard !pictures.isEmpty else { return }
        var avcc = Data()
        for unit in pictures {
            var size = UInt32(unit.count).bigEndian
            withUnsafeBytes(of: &size) { avcc.append(contentsOf: $0) }
            avcc.append(unit)
        }
        guard let sample = makeSample(avcc, format: format,
                                      pts: CMTime(value: CMTimeValue(ptsMicroseconds), timescale: 1_000_000),
                                      isKeyFrame: isKeyFrame) else { return }
        if layer.status == .failed { layer.flush() }
        layer.enqueue(sample)
    }

    private func makeFormat() -> CMVideoFormatDescription? {
        guard let sps, let pps else { return nil }
        var description: CMFormatDescription?
        let status = sps.withUnsafeBytes { spsRaw in
            pps.withUnsafeBytes { ppsRaw in
                let pointers: [UnsafePointer<UInt8>] = [
                    spsRaw.bindMemory(to: UInt8.self).baseAddress!,
                    ppsRaw.bindMemory(to: UInt8.self).baseAddress!
                ]
                let sizes = [sps.count, pps.count]
                return CMVideoFormatDescriptionCreateFromH264ParameterSets(
                    allocator: kCFAllocatorDefault,
                    parameterSetCount: 2,
                    parameterSetPointers: pointers,
                    parameterSetSizes: sizes,
                    nalUnitHeaderLength: 4,
                    formatDescriptionOut: &description)
            }
        }
        return status == noErr ? description : nil
    }

    private func makeSample(_ data: Data, format: CMFormatDescription, pts: CMTime,
                            isKeyFrame: Bool) -> CMSampleBuffer? {
        var block: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: data.count,
            blockAllocator: kCFAllocatorDefault, customBlockSource: nil,
            offsetToData: 0, dataLength: data.count, flags: 0, blockBufferOut: &block) == kCMBlockBufferNoErr,
              let block else { return nil }
        let copied = data.withUnsafeBytes { raw in
            CMBlockBufferReplaceDataBytes(with: raw.baseAddress!, blockBuffer: block,
                                          offsetIntoDestination: 0, dataLength: data.count)
        }
        guard copied == noErr else { return nil }
        var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: pts,
                                        decodeTimeStamp: .invalid)
        var size = data.count
        var sample: CMSampleBuffer?
        guard CMSampleBufferCreateReady(allocator: kCFAllocatorDefault,
                                        dataBuffer: block,
                                        formatDescription: format,
                                        sampleCount: 1,
                                        sampleTimingEntryCount: 1,
                                        sampleTimingArray: &timing,
                                        sampleSizeEntryCount: 1,
                                        sampleSizeArray: &size,
                                        sampleBufferOut: &sample) == noErr,
              let sample else { return nil }
        if !isKeyFrame, let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true) {
            let dictionary = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(dictionary,
                                 Unmanaged.passUnretained(kCMSampleAttachmentKey_NotSync).toOpaque(),
                                 Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
        }
        return sample
    }
}

enum NALUnits {
    static func split(_ data: Data) -> [Data] {
        let bytes = [UInt8](data)
        if bytes.count >= 4 && bytes[0] == 0 && bytes[1] == 0 && (bytes[2] == 1 || (bytes[2] == 0 && bytes[3] == 1)) {
            var starts: [(Int, Int)] = []
            var i = 0
            while i + 3 < bytes.count {
                if bytes[i] == 0 && bytes[i + 1] == 0 && bytes[i + 2] == 1 {
                    starts.append((i, 3)); i += 3
                } else if i + 4 <= bytes.count && bytes[i] == 0 && bytes[i + 1] == 0 && bytes[i + 2] == 0 && bytes[i + 3] == 1 {
                    starts.append((i, 4)); i += 4
                } else { i += 1 }
            }
            return starts.enumerated().compactMap { index, item in
                let begin = item.0 + item.1
                let end = index + 1 < starts.count ? starts[index + 1].0 : bytes.count
                return begin < end ? Data(bytes[begin..<end]) : nil
            }
        }
        var units: [Data] = []
        var offset = 0
        while offset + 4 <= bytes.count {
            let length = Int(UInt32(bytes[offset]) << 24 | UInt32(bytes[offset + 1]) << 16 |
                             UInt32(bytes[offset + 2]) << 8 | UInt32(bytes[offset + 3]))
            offset += 4
            guard length > 0, offset + length <= bytes.count else { return [data] }
            units.append(Data(bytes[offset..<(offset + length)]))
            offset += length
        }
        return units.isEmpty ? [data] : units
    }
}
