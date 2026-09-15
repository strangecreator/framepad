import AppKit
import AVFoundation
import SwiftUI
import FramepadCore

final class PlayerSurface: NSView {
    let playerLayer = AVPlayerLayer()
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect); wantsLayer = true; layer?.backgroundColor = NSColor.black.cgColor
        playerLayer.videoGravity = .resizeAspect; layer?.addSublayer(playerLayer)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layout() { super.layout(); CATransaction.begin(); CATransaction.setDisableActions(true); playerLayer.frame = bounds; CATransaction.commit() }
    override func mouseDown(with event: NSEvent) { window?.makeFirstResponder(self) }
    override var acceptsFirstResponder: Bool { true }
}
struct NativePlayer: NSViewRepresentable {
    let player: AVPlayer
    func makeNSView(context: Context) -> PlayerSurface { let view = PlayerSurface(); view.playerLayer.player = player; return view }
    func updateNSView(_ view: PlayerSurface, context: Context) { view.playerLayer.player = player }
}

struct VideoCanvas: View {
    @ObservedObject var model: AppModel
    @ObservedObject var video: VideoEngine
    var body: some View {
        GeometryReader { geometry in
            let rect = fittedRect(in: geometry.size)
            ZStack(alignment: .topLeading) {
                NativePlayer(player: video.player)
                if let crop = model.crop {
                    let selection = CGRect(x: rect.minX + crop.x * rect.width, y: rect.minY + crop.y * rect.height, width: crop.width * rect.width, height: crop.height * rect.height)
                    Path { path in path.addRect(rect); path.addRect(selection) }
                        .fill(.black.opacity(0.48), style: FillStyle(eoFill: true)).allowsHitTesting(false)
                    Rectangle().stroke(Palette.accent, lineWidth: 1).frame(width: selection.width, height: selection.height).position(x: selection.midX, y: selection.midY).allowsHitTesting(false)
                    ForEach(0..<4) { corner in
                        let x = corner % 2 == 0 ? selection.minX : selection.maxX
                        let y = corner < 2 ? selection.minY : selection.maxY
                        Rectangle().fill(Palette.accent).frame(width: 6, height: 6).position(x: x, y: y)
                    }.allowsHitTesting(false)
                    Text("\(Int((crop.width * video.videoSize.width).rounded())) × \(Int((crop.height * video.videoSize.height).rounded()))")
                        .font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(Palette.background)
                        .padding(.horizontal, 6).padding(.vertical, 4).background(Palette.accent, in: RoundedRectangle(cornerRadius: 4))
                        .position(x: min(max(selection.midX, rect.minX + 55), rect.maxX - 55), y: max(rect.minY + 12, selection.minY - 15)).allowsHitTesting(false)
                }
                CropInteraction(model: model, videoRect: rect, videoSize: video.videoSize)
                if model.missingVideo {
                    unavailable.frame(maxWidth: .infinity, maxHeight: .infinity).background(Palette.background)
                } else if video.duration == 0 {
                    VStack(spacing: 14) {
                        if video.status != "Video unavailable" { ProgressView().controlSize(.small).tint(Palette.accent) }
                        Text(video.status).font(.system(size: 12)).foregroundStyle(Palette.secondary)
                        if video.status == "Video unavailable" { Button("Locate video", action: model.relinkVideo).buttonStyle(QuietButtonStyle()) }
                    }.frame(maxWidth: .infinity, maxHeight: .infinity).background(Palette.background)
                }
                if video.duration > 0 {
                    HStack(spacing: 6) {
                        Circle().fill(video.playing ? Palette.accent : Palette.secondary).frame(width: 5, height: 5)
                        Text(video.playing ? "PLAYING" : "PAUSED").font(.system(size: 9, weight: .semibold)).tracking(1)
                    }.foregroundStyle(Palette.text).padding(.horizontal, 10).padding(.vertical, 7)
                        .background(.black.opacity(0.55), in: Capsule()).padding(16).allowsHitTesting(false)
                }
                if model.cropMode {
                    VStack { Spacer(); HStack { Spacer(); Text("Drag a region · Resize edges · ⌘W to clear").font(.system(size: 11)).padding(.horizontal, 13).padding(.vertical, 8).background(.black.opacity(0.75), in: Capsule()); Spacer() }.padding(.bottom, 16) }.allowsHitTesting(false)
                }
            }.clipped()
        }.background(.black)
    }
    private func fittedRect(in size: CGSize) -> CGRect {
        let ratio = min(size.width / max(1, video.videoSize.width), size.height / max(1, video.videoSize.height))
        let w = video.videoSize.width * ratio, h = video.videoSize.height * ratio
        return CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h)
    }
    private var unavailable: some View {
        VStack(spacing: 14) {
            Image(systemName: "video.slash").font(.system(size: 32, weight: .light)).foregroundStyle(Palette.muted)
            Text("Let’s find your video").font(.system(size: 19, weight: .medium))
            Text("The original file has moved or is unavailable.\nYour notes and captures are safe in this project.").font(.system(size: 12)).foregroundStyle(Palette.secondary).multilineTextAlignment(.center)
            Button("Locate video", action: model.relinkVideo).buttonStyle(AccentButtonStyle()).padding(.top, 3)
        }
    }
}

struct VideoPane: View {
    @ObservedObject var model: AppModel
    @ObservedObject var video: VideoEngine
    @State private var scrubbing = false
    @State private var resumeAfterScrub = false
    @State private var hoverX: CGFloat?
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 9) {
                SectionLabel(title: "Video")
                Text("/").foregroundStyle(Palette.muted)
                Text(model.project.map { URL(fileURLWithPath: $0.videoPath).lastPathComponent } ?? "")
                    .font(.system(size: 11)).foregroundStyle(Palette.secondary).lineLimit(1).truncationMode(.middle)
                Spacer()
                if model.crop != nil { Button("Clear crop", action: model.clearCrop).buttonStyle(PointerButtonStyle()).font(.system(size: 11)).foregroundStyle(Palette.secondary).help("Remove the crop (⌘W)") }
                IconButton(symbol: "crop", help: "Create or edit a crop (⌘⇧C)", active: model.cropMode, action: model.toggleCrop).disabled(!video.ready)
            }.padding(.horizontal, 17).frame(height: 45)
            VideoCanvas(model: model, video: video).padding(.horizontal, 12)
                .clipShape(RoundedRectangle(cornerRadius: 7))
            VStack(spacing: 9) {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Palette.raised).frame(height: 4)
                        Capsule().fill(Palette.accent).frame(width: max(0, geometry.size.width * progress), height: 4)
                        TimelineMarkers(times: model.markerTimes, duration: video.duration).equatable().frame(height: 4).allowsHitTesting(false)
                        Circle().fill(Palette.accent).frame(width: scrubbing || hoverX != nil ? 12 : 9, height: scrubbing || hoverX != nil ? 12 : 9).offset(x: max(0, min(geometry.size.width - 9, geometry.size.width * progress - 4.5)))
                        if let hoverX {
                            Capsule().fill(Palette.accent.opacity(0.45)).frame(width: 2, height: 12).offset(x: hoverX - 1)
                        }
                    }.frame(maxHeight: .infinity).contentShape(Rectangle())
                        .pointerCursor(enabled: video.ready && !model.isSaving) { point in
                            hoverX = point.map { min(max(0, $0.x), geometry.size.width) }
                        }
                        .overlay(alignment: .topLeading) {
                            if let hoverX, video.duration > 0 {
                                TimeLabel(seconds: hoverX / max(1, geometry.size.width) * video.duration, size: 10, highlighted: true)
                                    .frame(width: 104, height: 30).background(Palette.raised, in: RoundedRectangle(cornerRadius: 8))
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.16)))
                                    .shadow(color: .black.opacity(0.35), radius: 8, y: 3)
                                    .offset(x: min(max(0, hoverX - 52), max(0, geometry.size.width - 104)), y: -36)
                                    .allowsHitTesting(false).accessibilityIdentifier("video-hover-time")
                                    .transition(.opacity)
                            }
                        }
                        .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                            guard video.duration > 0, !model.isSaving else { return }
                            if !scrubbing { resumeAfterScrub = video.playing; video.pause(); scrubbing = true }
                            hoverX = min(max(0, value.location.x), geometry.size.width)
                            video.seek(value.location.x / max(1, geometry.size.width) * video.duration)
                        }.onEnded { _ in scrubbing = false; hoverX = nil; if resumeAfterScrub { video.toggle() }; resumeAfterScrub = false })
                        .accessibilityElement(children: .contain).accessibilityLabel("Video progress").accessibilityValue(Timecode.string(video.position))
                        .accessibilityAdjustableAction { direction in video.skip(direction == .increment ? 3 : -3) }
                }.frame(height: 22)
                HStack(spacing: 10) {
                    TimeLabel(seconds: video.position, size: 11, highlighted: true)
                    Text("/").foregroundStyle(Palette.muted).font(.system(size: 11))
                    TimeLabel(seconds: video.duration, size: 11)
                    Spacer(minLength: 8)
                    if video.ready {
                        Text("FRAME \(video.currentFrame.formatted(.number.grouping(.never)))").font(.system(size: 9, weight: .medium, design: .monospaced)).tracking(0.5).foregroundStyle(Palette.muted)
                    } else { Text(video.status).font(.system(size: 10)).foregroundStyle(Palette.muted) }
                    Rectangle().fill(Palette.border).frame(width: 1, height: 12).padding(.horizontal, 3)
                    KeyCap(text: "⌥ space"); Text("play / pause").font(.system(size: 10)).foregroundStyle(Palette.muted)
                    KeyCap(text: "← →"); Text("3s").font(.system(size: 10)).foregroundStyle(Palette.muted)
                }
            }.padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 15)
        }.background(Palette.surface)
    }
    var progress: Double { max(0, min(1, video.position / max(0.001, video.duration))) }
}

struct TimelineMarkers: View, Equatable {
    var times: [Double]
    var duration: Double
    var body: some View {
        Canvas { context, size in
            guard duration > 0 else { return }
            var pixels = Set<Int>()
            for time in times {
                let pixel = Int(max(0, min(size.width - 4, size.width * time / duration)))
                if pixels.insert(pixel / 3).inserted {
                    context.fill(Path(ellipseIn: CGRect(x: pixel, y: 0, width: 4, height: 4)), with: .color(Palette.accent.opacity(0.65)))
                }
            }
        }
    }
}
