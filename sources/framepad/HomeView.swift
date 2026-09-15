import SwiftUI

struct HomeView: View {
    @ObservedObject var model: AppModel
    @State private var search = ""
    var filtered: [RecentProject] { model.recents.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || $0.videoName.localizedCaseInsensitiveContains(search) } }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 11) {
                BrandMark(size: 27)
                Text("framepad").font(.system(size: 19, weight: .semibold, design: .rounded)).tracking(-0.6)
                Rectangle().fill(Palette.border).frame(width: 1, height: 19).padding(.horizontal, 10)
                Text("Your workspace").font(.system(size: 12)).foregroundStyle(Palette.secondary)
                Spacer()
                Button { model.showShortcuts = true } label: { Label("Keyboard shortcuts", systemImage: "command") }.buttonStyle(PointerButtonStyle()).foregroundStyle(Palette.secondary).font(.system(size: 12))
            }.padding(.horizontal, 36).frame(height: 70)
            Rectangle().fill(Palette.border).frame(height: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 34) {
                    HStack(alignment: .center, spacing: 60) {
                        VStack(alignment: .leading, spacing: 18) {
                            HStack(spacing: 7) { Circle().fill(Palette.accent).frame(width: 5, height: 5); SectionLabel(title: "A closer look") }
                            Text("Every frame.\nEvery thought.").font(.system(size: 48, weight: .medium)).tracking(-2).lineSpacing(-2)
                            Text("Capture the detail. Add your perspective.\nTurn your footage into a collection of ideas.")
                                .font(.system(size: 14)).foregroundStyle(Palette.secondary).lineSpacing(6)
                            HStack(spacing: 10) {
                                Button(action: model.newProject) { Label("New project", systemImage: "plus") }.buttonStyle(AccentButtonStyle())
                                Button(action: model.openProject) { Label("Open project", systemImage: "folder") }.buttonStyle(QuietButtonStyle())
                            }.padding(.top, 7)
                            Text("LOCAL VIDEO. YOUR NOTES. ALL IN ONE PLACE.").font(.system(size: 9, weight: .medium)).tracking(1.3).foregroundStyle(Palette.muted).padding(.top, 2)
                        }
                        Spacer(minLength: 0)
                        HomeArtwork().frame(width: 380, height: 280).accessibilityHidden(true)
                    }.padding(.vertical, 24)
                    Rectangle().fill(Palette.border).frame(height: 1)
                    HStack {
                        Text("Your projects").font(.system(size: 20, weight: .medium)).tracking(-0.5)
                        Text("\(model.recents.count)").font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.secondary)
                            .padding(.horizontal, 7).padding(.vertical, 3).background(Palette.raised, in: Capsule())
                        Spacer()
                        if !model.recents.isEmpty {
                            HStack(spacing: 8) { Image(systemName: "magnifyingglass"); TextField("Find a project…", text: $search).textFieldStyle(.plain) }
                                .font(.system(size: 12)).foregroundStyle(Palette.secondary).padding(9).frame(width: 220)
                                .background(Palette.surface, in: RoundedRectangle(cornerRadius: 8)).overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.border))
                        }
                    }
                    if model.recents.isEmpty {
                        HStack(spacing: 20) {
                            Image(systemName: "rectangle.stack").font(.system(size: 28, weight: .light)).foregroundStyle(Palette.muted)
                            VStack(alignment: .leading, spacing: 7) {
                                Text("A fresh workspace").font(.system(size: 14, weight: .medium))
                                Text("Choose a video to start your first project. Your saved projects will appear here.").font(.system(size: 12)).foregroundStyle(Palette.secondary)
                            }
                            Spacer()
                            Button(action: model.newProject) { Image(systemName: "arrow.up.right").font(.system(size: 18)) }.buttonStyle(PointerButtonStyle()).foregroundStyle(Palette.accent).help("Create your first project")
                        }.padding(30).frame(maxWidth: .infinity, alignment: .leading)
                            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 13))
                            .overlay(RoundedRectangle(cornerRadius: 13).stroke(Palette.border))
                    } else if filtered.isEmpty {
                        Text("No matching projects.").foregroundStyle(Palette.secondary).padding(.vertical, 30)
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 270), spacing: 16)], spacing: 16) {
                            ForEach(filtered) { recent in
                                Button { model.openRecent(recent) } label: { ProjectCard(recent: recent) }.buttonStyle(PointerButtonStyle(cornerRadius: 12, minimumSize: 0, horizontalPadding: 0))
                                    .contextMenu { Button("Remove from recent projects") { model.removeRecent(recent) } }
                            }
                        }
                    }
                    HStack(spacing: 6) { Image(systemName: "internaldrive"); Text("Saved on your Mac. Ready when you are.") }
                        .font(.system(size: 11)).foregroundStyle(Palette.muted).padding(.top, 4)
                }.padding(.horizontal, 56).padding(.bottom, 40).frame(maxWidth: 1260)
                    .frame(maxWidth: .infinity)
            }
        }.background(Palette.background)
    }
}

struct ProjectCard: View {
    var recent: RecentProject
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Image(systemName: "film").font(.system(size: 19)).foregroundStyle(Palette.accent).frame(width: 42, height: 42)
                    .background(Palette.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
                Spacer()
                Image(systemName: "arrow.up.right").foregroundStyle(Palette.muted)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(recent.title).font(.system(size: 15, weight: .medium)).lineLimit(1)
                Text(recent.videoName).font(.system(size: 11)).foregroundStyle(Palette.muted).lineLimit(1)
            }
            HStack { Text("\(recent.count) vboxes"); Spacer(); Text(recent.modified, style: .relative).lineLimit(1) }
                .font(.system(size: 10)).foregroundStyle(Palette.secondary)
        }.padding(20).background(Palette.surface, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.border))
    }
}

struct HomeArtwork: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20).stroke(Palette.border).frame(width: 320, height: 212).rotationEffect(.degrees(-9)).offset(x: -8, y: -2)
            VStack(spacing: 0) {
                ZStack {
                    LinearGradient(colors: [Color(hex: 0x334238), Color(hex: 0x182323)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    Canvas { context, size in
                        for i in 0..<9 {
                            var path = Path(); let y = CGFloat(i) * 20 + 50
                            path.move(to: CGPoint(x: -20, y: y))
                            path.addCurve(to: CGPoint(x: size.width + 20, y: y - 10), control1: CGPoint(x: size.width * 0.25, y: y - 100), control2: CGPoint(x: size.width * 0.7, y: y + 120))
                            context.stroke(path, with: .color(Palette.accent.opacity(0.12)), lineWidth: 1)
                        }
                    }
                    RoundedRectangle(cornerRadius: 3).stroke(Palette.accent, style: StrokeStyle(lineWidth: 1.3, dash: [5, 3])).frame(width: 122, height: 84)
                    Image(systemName: "plus").font(.system(size: 16, weight: .ultraLight)).foregroundStyle(Palette.accent)
                    VStack { HStack { Text("FRAME 0042").font(.system(size: 8, design: .monospaced)).tracking(1); Spacer(); Circle().fill(Palette.accent).frame(width: 5, height: 5) }; Spacer() }.foregroundStyle(Palette.accent.opacity(0.6)).padding(16)
                }.frame(height: 165).clipShape(UnevenRoundedRectangle(topLeadingRadius: 13, topTrailingRadius: 13))
                HStack { TimeLabel(seconds: 1.75, size: 10); Spacer(); Image(systemName: "waveform").foregroundStyle(Palette.accent) }.padding(14).background(Palette.raised)
            }.frame(width: 306).clipShape(RoundedRectangle(cornerRadius: 13)).overlay(RoundedRectangle(cornerRadius: 13).stroke(Color.white.opacity(0.12))).rotationEffect(.degrees(3))
            HStack(spacing: 10) {
                Image(systemName: "text.alignleft").foregroundStyle(Palette.accent)
                VStack(alignment: .leading, spacing: 4) { Text("A little detail. A bigger idea.").font(.system(size: 10, weight: .medium)); Text("CAPTURE · ANNOTATE · CONNECT").font(.system(size: 7, weight: .medium)).tracking(1).foregroundStyle(Palette.muted) }
            }.padding(14).background(Palette.surface, in: RoundedRectangle(cornerRadius: 10)).overlay(RoundedRectangle(cornerRadius: 10).stroke(Palette.border)).shadow(color: .black.opacity(0.3), radius: 15, y: 10).offset(x: 46, y: 110)
        }
    }
}
