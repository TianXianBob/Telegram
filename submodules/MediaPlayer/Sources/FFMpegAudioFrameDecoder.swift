import Foundation
import CoreMedia
import FFMpeg

final class FFMpegAudioFrameDecoder: MediaTrackFrameDecoder {
    private let codecContext: FFMpegAVCodecContext
    private let swrContext: FFMpegSWResample
    
    private let audioFrame: FFMpegAVFrame
    private var resetDecoderOnNextFrame = true
    
    private var delayedFrames: [MediaTrackFrame] = []
    
    init(codecContext: FFMpegAVCodecContext) {
        self.codecContext = codecContext
        self.audioFrame = FFMpegAVFrame()
        
        self.swrContext = FFMpegSWResample(sourceChannelCount: Int(codecContext.channels()), sourceSampleRate: Int(codecContext.sampleRate()), sourceSampleFormat: codecContext.sampleFormat(), destinationChannelCount: 2, destinationSampleRate: 44100, destinationSampleFormat: FFMPEG_AV_SAMPLE_FMT_S16)
    }
    
    func decode(frame: MediaTrackDecodableFrame) -> MediaTrackFrame? {
        let status = frame.packet.send(toDecoder: self.codecContext)
        if status == 0 {
            while self.codecContext.receive(into: self.audioFrame) {
                if let convertedFrame = convertAudioFrame(self.audioFrame, pts: frame.pts, duration: frame.duration) {
                    self.delayedFrames.append(convertedFrame)
                }
            }
            
            if self.delayedFrames.count >= 1 {
                var minFrameIndex = 0
                var minPosition = self.delayedFrames[0].position
                for i in 1 ..< self.delayedFrames.count {
                    if CMTimeCompare(self.delayedFrames[i].position, minPosition) < 0 {
                        minFrameIndex = i
                        minPosition = self.delayedFrames[i].position
                    }
                }
                return self.delayedFrames.remove(at: minFrameIndex)
            }
        }
        
        return nil
    }
    
    func takeQueuedFrame() -> MediaTrackFrame? {
        if self.delayedFrames.count >= 1 {
            var minFrameIndex = 0
            var minPosition = self.delayedFrames[0].position
            for i in 1 ..< self.delayedFrames.count {
                if CMTimeCompare(self.delayedFrames[i].position, minPosition) < 0 {
                    minFrameIndex = i
                    minPosition = self.delayedFrames[i].position
                }
            }
            return self.delayedFrames.remove(at: minFrameIndex)
        } else {
            return nil
        }
    }
    
    func takeRemainingFrame() -> MediaTrackFrame? {
        if !self.delayedFrames.isEmpty {
            var minFrameIndex = 0
            var minPosition = self.delayedFrames[0].position
            for i in 1 ..< self.delayedFrames.count {
                if CMTimeCompare(self.delayedFrames[i].position, minPosition) < 0 {
                    minFrameIndex = i
                    minPosition = self.delayedFrames[i].position
                }
            }
            return self.delayedFrames.remove(at: minFrameIndex)
        } else {
            return nil
        }
    }
    
    private func convertAudioFrame(_ frame: FFMpegAVFrame, pts: CMTime, duration: CMTime) -> MediaTrackFrame? {
        guard let data = self.swrContext.resample(frame) else {
            return nil
        }
        
        var blockBuffer: CMBlockBuffer?
        
        let bytes = malloc(data.count)!
        data.copyBytes(to: bytes.assumingMemoryBound(to: UInt8.self), count: data.count)
        let status = CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: bytes, blockLength: data.count, blockAllocator: nil, customBlockSource: nil, offsetToData: 0, dataLength: data.count, flags: 0, blockBufferOut: &blockBuffer)
        if status != noErr {
            return nil
        }
        
        var timingInfo = CMSampleTimingInfo(duration: duration, presentationTimeStamp: pts, decodeTimeStamp: pts)
        var sampleBuffer: CMSampleBuffer?
        var sampleSize = data.count
        guard CMSampleBufferCreate(allocator: nil, dataBuffer: blockBuffer, dataReady: true, makeDataReadyCallback: nil, refcon: nil, formatDescription: nil, sampleCount: 1, sampleTimingEntryCount: 1, sampleTimingArray: &timingInfo, sampleSizeEntryCount: 1, sampleSizeArray: &sampleSize, sampleBufferOut: &sampleBuffer) == noErr else {
            return nil
        }
        
        let resetDecoder = self.resetDecoderOnNextFrame
        self.resetDecoderOnNextFrame = false
        
        return MediaTrackFrame(type: .audio, sampleBuffer: sampleBuffer!, resetDecoder: resetDecoder, decoded: true)
    }
    
    func reset() {
        self.codecContext.flushBuffers()
        self.resetDecoderOnNextFrame = true
    }
}
