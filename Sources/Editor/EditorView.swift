import SwiftUI

struct EditorView: View {
    @ObservedObject var doc: EditorDocument

    var body: some View {
        VStack(spacing: 0) {
            EditorToolbar(doc: doc)
            Divider()
            GeometryReader { geo in
                let fit = fitScale(in: geo.size)
                ZStack {
                    Color(nsColor: .underPageBackgroundColor)
                    EditorCanvas(doc: doc, fitScale: fit)
                        .clipShape(RoundedRectangle(cornerRadius: doc.cornerRadius * doc.unit * fit))
                        .overlay {
                            if doc.borderOn {
                                RoundedRectangle(cornerRadius: doc.cornerRadius * doc.unit * fit)
                                    .strokeBorder(doc.borderColor, lineWidth: max(0.5, doc.borderWidth * doc.unit * fit))
                            }
                        }
                        .shadow(
                            color: doc.shadowOn ? .black.opacity(0.4) : .clear,
                            radius: doc.shadowOn ? 12 * fit * doc.unit : 0,
                            y: doc.shadowOn ? 5 * fit * doc.unit : 0
                        )
                }
            }
        }
        .frame(minWidth: 700, minHeight: 440)
    }

    /// Fit the image inside the available space, never exceeding its natural
    /// (point) size.
    private func fitScale(in available: CGSize) -> CGFloat {
        let margin: CGFloat = 24
        let w = max(100, available.width - margin * 2)
        let h = max(100, available.height - margin * 2)
        return min(w / doc.pixelSize.width, h / doc.pixelSize.height, 1 / doc.unit)
    }
}

// MARK: - Toolbar

struct EditorToolbar: View {
    @ObservedObject var doc: EditorDocument
    /// Office-style ribbon: big tool buttons with names. Off = compact icons.
    @AppStorage("editorRibbon") private var showRibbon = true

    private let strokeWidths: [CGFloat] = [2, 4, 6, 10]
    private let fontSizes: [CGFloat] = [14, 18, 22, 28, 36, 48]

    var body: some View {
        VStack(spacing: 0) {
            if showRibbon {
                ribbonRow
                Divider()
            }
            controlRow
        }
        .background(.bar)
    }

    private var ribbonRow: some View {
        HStack(spacing: 2) {
            ForEach(Tool.allCases) { tool in
                Button {
                    doc.tool = tool
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tool.symbol)
                            .font(.system(size: 16, weight: .medium))
                            .frame(height: 18)
                        Text(tool.label)
                            .font(.system(size: 10))
                    }
                    .frame(width: 48, height: 44)
                }
                .buttonStyle(.borderless)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(doc.tool == tool ? Color.accentColor.opacity(0.18) : .clear)
                )
                .foregroundStyle(doc.tool == tool ? Color.accentColor : Color.primary)
                .help(tool.help)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var controlRow: some View {
        HStack(spacing: 10) {
            if !showRibbon {
                toolButtons
                Divider().frame(height: 22)
            }
            styleControls
            Divider().frame(height: 22)
            historyControls

            if doc.cropDraft != nil {
                Divider().frame(height: 22)
                Button("Apply Crop") { doc.applyCrop() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: [])
                Button("Cancel") { doc.cancelCrop() }
                    .keyboardShortcut(.cancelAction)
            }

            Spacer()

            effectsMenu

            ShareButton(image: { doc.renderFinal() }, scale: doc.scale)

            Button {
                doc.copyFlattened()
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])
            .help("Copy flattened image (⇧⌘C)")

            Button {
                doc.saveFlattened()
            } label: {
                Label("Save…", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut("s", modifiers: .command)
            .help("Save as PNG (⌘S)")

            Button {
                showRibbon.toggle()
            } label: {
                Image(systemName: showRibbon ? "chevron.up" : "chevron.down")
            }
            .buttonStyle(.borderless)
            .help(showRibbon ? "Hide Tool Ribbon" : "Show Tool Ribbon")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var toolButtons: some View {
        HStack(spacing: 2) {
            ForEach(Tool.allCases) { tool in
                Button {
                    doc.tool = tool
                } label: {
                    Image(systemName: tool.symbol)
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: 26, height: 24)
                }
                .buttonStyle(.borderless)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(doc.tool == tool ? Color.accentColor.opacity(0.22) : .clear)
                )
                .foregroundStyle(doc.tool == tool ? Color.accentColor : Color.primary)
                .help(tool.help)
            }
        }
    }

    private var styleControls: some View {
        HStack(spacing: 8) {
            ColorPicker("", selection: $doc.color, supportsOpacity: false)
                .labelsHidden()
                .frame(width: 28)
                .help("Color")

            Menu {
                ForEach(strokeWidths, id: \.self) { width in
                    Button {
                        doc.strokeWidth = width
                    } label: {
                        HStack {
                            Text("\(Int(width)) pt")
                            if doc.strokeWidth == width { Image(systemName: "checkmark") }
                        }
                    }
                }
            } label: {
                Image(systemName: "lineweight")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 44)
            .help("Line Weight")

            Menu {
                ForEach(fontSizes, id: \.self) { size in
                    Button {
                        doc.fontSize = size
                    } label: {
                        HStack {
                            Text("\(Int(size)) pt")
                            if doc.fontSize == size { Image(systemName: "checkmark") }
                        }
                    }
                }
            } label: {
                Image(systemName: "textformat.size")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 44)
            .help("Text Size")
        }
    }

    private var historyControls: some View {
        HStack(spacing: 2) {
            Button {
                doc.undo()
            } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .buttonStyle(.borderless)
            .disabled(!doc.canUndo)
            .keyboardShortcut("z", modifiers: .command)
            .help("Undo (⌘Z)")

            Button {
                doc.redo()
            } label: {
                Image(systemName: "arrow.uturn.forward")
            }
            .buttonStyle(.borderless)
            .disabled(!doc.canRedo)
            .keyboardShortcut("z", modifiers: [.command, .shift])
            .help("Redo (⇧⌘Z)")

            Button {
                doc.deleteSelected()
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .disabled(doc.selectedID == nil || doc.editingID != nil)
            .keyboardShortcut(.delete, modifiers: [])
            .help("Delete Selection (⌫)")
        }
    }

    private var effectsMenu: some View {
        Menu {
            Toggle("Border", isOn: $doc.borderOn)
            Toggle("Drop Shadow", isOn: $doc.shadowOn)
            Menu("Corner Radius") {
                ForEach([0, 8, 14, 24], id: \.self) { (radius: Int) in
                    Button {
                        doc.cornerRadius = CGFloat(radius)
                    } label: {
                        HStack {
                            Text(radius == 0 ? "None" : "\(radius) pt")
                            if Int(doc.cornerRadius) == radius { Image(systemName: "checkmark") }
                        }
                    }
                }
            }
            if doc.borderOn {
                Menu("Border Width") {
                    ForEach([2, 3, 5, 8], id: \.self) { (width: Int) in
                        Button {
                            doc.borderWidth = CGFloat(width)
                        } label: {
                            HStack {
                                Text("\(width) pt")
                                if Int(doc.borderWidth) == width { Image(systemName: "checkmark") }
                            }
                        }
                    }
                }
            }
        } label: {
            Label("Effects", systemImage: "sparkles")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Border, shadow, and corner effects applied to the exported image")
    }
}
