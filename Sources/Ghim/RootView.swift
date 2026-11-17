import SwiftUI

struct RootView: View {
    @EnvironmentObject var pc: PanelController
    @EnvironmentObject var prefs: Prefs

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if prefs.edgeRight {
                contentSlot
                TabStrip().padding(.top, pc.stripOffset)
            } else {
                TabStrip().padding(.top, pc.stripOffset)
                contentSlot
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: prefs.edgeRight ? .topTrailing : .topLeading)
    }

    @ViewBuilder private var contentSlot: some View {
        if pc.expanded {
            ZStack {
                if pc.showContent {
                    ContentPanel()
                        .transition(.move(edge: prefs.edgeRight ? .trailing : .leading).combined(with: .opacity))
                }
            }
            .frame(width: pc.contentWidth)
            .frame(maxHeight: .infinity)
            .simultaneousGesture(TapGesture().onEnded { pc.userInteracted() })
        }
    }
}

// MARK: - The edge strip

struct TabStrip: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var pc: PanelController
    @EnvironmentObject var prefs: Prefs
    @EnvironmentObject var timer: FocusTimer

    var body: some View {
        VStack(alignment: prefs.edgeRight ? .trailing : .leading, spacing: TabMetrics.spacing) {
            Grip()
            TodayTab()
            if timer.active { FocusTab() }
            ForEach(store.data.categories) { c in
                CategoryTab(category: c)
            }
        }
        .frame(width: TabMetrics.stripWidth, alignment: prefs.edgeRight ? .trailing : .leading)
    }
}

private struct Grip: View {
    @EnvironmentObject var pc: PanelController
    @EnvironmentObject var prefs: Prefs
    @State private var hover = false

    var body: some View {
        ZStack {
            TabShape(right: prefs.edgeRight, radius: 7)
                .fill(Color(white: 0.16).opacity(hover ? 0.95 : 0.8))
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white.opacity(0.75))
        }
        .frame(width: hover ? TabMetrics.stripWidth : TabMetrics.restWidth, height: TabMetrics.gripHeight)
        .contentShape(Rectangle())
        .onHover { h in
            withAnimation(.easeOut(duration: 0.12)) { hover = h }
            if h { NSCursor.openHand.push() } else { NSCursor.pop() }
        }
        .gesture(
            DragGesture(minimumDistance: 2, coordinateSpace: .global)
                .onChanged { _ in pc.dragChanged() }
                .onEnded { _ in pc.dragEnded() }
        )
        .onTapGesture { pc.toggle() }
        .help("Kéo để đổi vị trí · bấm để mở/đóng")
    }
}

private struct TodayTab: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var pc: PanelController
    @EnvironmentObject var prefs: Prefs
    @State private var hover = false

    var selected: Bool { pc.expanded && pc.selection == .today }

    var body: some View {
        let p = store.todayProgress
        let frac = p.total > 0 ? Double(p.done) / Double(p.total) : 0
        let allDone = p.total > 0 && p.done == p.total
        VStack(spacing: 4) {
            ZStack {
                ProgressRing(progress: frac, color: allDone ? .green : .orange, lineWidth: 2.2)
                Image(systemName: allDone ? "checkmark" : "sun.max.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(allDone ? .green : .orange)
            }
            .frame(width: 20, height: 20)
            Text(p.total > 0 ? "\(p.done)/\(p.total)" : "–")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(width: (hover || selected) ? TabMetrics.stripWidth : TabMetrics.restWidth, height: TabMetrics.todayHeight)
        .background(TabShape(right: prefs.edgeRight).fill(Color(white: 0.16)))
        .overlay(TabShape(right: prefs.edgeRight).stroke(Color.white.opacity(selected ? 0.5 : 0.08), lineWidth: selected ? 1 : 0.5))
        .contentShape(Rectangle())
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hover = h } }
        .onTapGesture { pc.select(.today) }
        .help("Hôm nay: \(p.done)/\(p.total) việc")
    }
}

private struct FocusTab: View {
    @EnvironmentObject var timer: FocusTimer
    @EnvironmentObject var pc: PanelController
    @EnvironmentObject var prefs: Prefs
    @State private var hover = false

    var body: some View {
        let color: Color = timer.isBreak ? .green : Color(hex: "#FF5A5F")
        VStack(spacing: 3) {
            ZStack {
                ProgressRing(progress: timer.progress, color: .white, lineWidth: 2)
                Image(systemName: timer.isBreak ? "cup.and.saucer.fill" : (timer.running ? "timer" : "pause.fill"))
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 18, height: 18)
            Text("\(timer.minutesLeft)′")
                .font(.system(size: 10, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
        }
        .frame(width: (hover) ? TabMetrics.stripWidth : TabMetrics.restWidth, height: TabMetrics.focusHeight)
        .background(TabShape(right: prefs.edgeRight).fill(color.gradient))
        .contentShape(Rectangle())
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hover = h } }
        .onTapGesture { pc.expand() }
        .contextMenu {
            Button(timer.running ? "Tạm dừng" : "Tiếp tục") { timer.togglePause() }
            Button("+5 phút") { timer.addMinutes(5) }
            Button("Dừng") { timer.stop() }
        }
        .help(timer.isBreak ? "Đang nghỉ – còn \(timer.remainingString)" : "Đang tập trung – còn \(timer.remainingString)")
    }
}

private struct CategoryTab: View {
    let category: Category
    @EnvironmentObject var store: Store
    @EnvironmentObject var pc: PanelController
    @EnvironmentObject var prefs: Prefs
    @State private var hover = false

    var selected: Bool { pc.expanded && pc.selection == .category(category.id) }

    var body: some View {
        let ink = inkColor(on: category.colorHex)
        let count = category.kind == .tasks ? store.openCount(category.id) : 0
        let overdue = category.kind == .tasks ? store.overdueCount(category.id) : 0
        let textW = TabMetrics.textWidth(category.name)
        VStack(spacing: 5) {
            Text(category.name)
                .font(Font(TabMetrics.font))
                .foregroundStyle(ink)
                .lineLimit(1)
                .fixedSize()
                .rotationEffect(.degrees(prefs.edgeRight ? 90 : -90))
                .frame(width: 20, height: textW)
            if category.kind == .tasks {
                Text(count > 99 ? "99+" : "\(count)")
                    .font(.system(size: 9, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(overdue > 0 ? Color.white : ink.opacity(0.85))
                    .frame(minWidth: 17, minHeight: 14)
                    .background(Capsule().fill(overdue > 0 ? Color.red : ink.opacity(0.14)))
                    .opacity(count == 0 ? 0.45 : 1)
            }
        }
        .frame(width: (hover || selected) ? TabMetrics.stripWidth : TabMetrics.restWidth,
               height: TabMetrics.height(category))
        .background(
            TabShape(right: prefs.edgeRight)
                .fill(Color(hex: category.colorHex).gradient)
                .shadow(color: .black.opacity(selected ? 0.25 : 0.12), radius: selected ? 3 : 1, x: prefs.edgeRight ? -1 : 1)
        )
        .opacity(pc.expanded && !selected ? 0.82 : 1)
        .contentShape(Rectangle())
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hover = h } }
        .onTapGesture { pc.select(.category(category.id)) }
        .onDrop(of: category.kind == .notes ? ImageDrop.types : [], isTargeted: $hover) { providers in
            ImageDrop.load(providers) { payloads in
                guard !payloads.isEmpty else { return }
                store.attachImages(payloads, to: nil, category: category.id)
                Sound.play("Pop")
                pc.expand(.category(category.id))
            }
            return true
        }
        .help(overdue > 0 ? "\(category.name) – \(count) việc, \(overdue) quá hạn" : category.name)
        .contextMenu {
            Button("Mở \(category.name)") { pc.expand(.category(category.id)) }
            Button("Thêm nhanh vào \(category.name)…") { pc.expand(.category(category.id), focusInput: true) }
            Divider()
            Button("Sửa tab…") { SettingsWindow.show(tab: .tabs) }
        }
    }
}
