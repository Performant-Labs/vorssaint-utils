// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// What the hover tooltip shows: a headline (the sleep/keep-awake status,
/// same copy as the old plain-text tooltip) plus an optional table of live
/// metric readings (only present in sparkline/bar appearance modes, where
/// the menu bar itself no longer prints the number).
struct StatusItemHoverContent {
    let symbolName: String
    let headline: String
    let rows: [MenuBarRenderer.HoverMetricRow]

    var isEmpty: Bool { headline.isEmpty }

    static let empty = StatusItemHoverContent(symbolName: "moon.zzz.fill", headline: "", rows: [])
}

/// A custom-drawn hover tooltip for the status item, replacing the system
/// tooltip (`NSView.toolTip`). The system tooltip's font size and styling
/// aren't configurable through any public API — this exists purely to make
/// the sparkline summary (current CPU/GPU/network values) readable at a
/// glance instead of squinting at the fixed small system tooltip text.
///
/// Styled as a miniature of the app's own popover (same `.popover` material,
/// same rounded card, same secondary-label/primary-label hierarchy) rather
/// than an oversized HUD, so it reads as part of this app instead of a
/// generic overlay.
final class StatusItemHoverPanel {
    private let panel: NSPanel
    private let container: NSStackView
    private let headerIcon: NSImageView
    private let headerLabel: NSTextField
    private let separator: NSBox
    private let rowsGrid: NSGridView

    init() {
        let headerIcon = NSImageView()
        headerIcon.translatesAutoresizingMaskIntoConstraints = false
        headerIcon.widthAnchor.constraint(equalToConstant: 14).isActive = true
        headerIcon.heightAnchor.constraint(equalToConstant: 14).isActive = true
        self.headerIcon = headerIcon

        let headerLabel = NSTextField(labelWithString: "")
        headerLabel.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        headerLabel.textColor = .labelColor
        headerLabel.lineBreakMode = .byClipping
        self.headerLabel = headerLabel

        let headerStack = NSStackView(views: [headerIcon, headerLabel])
        headerStack.orientation = .horizontal
        headerStack.alignment = .centerY
        headerStack.spacing = 6

        let separator = NSBox()
        separator.boxType = .separator
        self.separator = separator

        // Column widths size to their widest cell automatically, which is
        // what gives the symbol/label/value columns their alignment across
        // rows — no manual width bookkeeping needed as rows come and go.
        let rowsGrid = NSGridView(numberOfColumns: 3, rows: 0)
        rowsGrid.columnSpacing = 6
        rowsGrid.rowSpacing = 3
        rowsGrid.column(at: 2).xPlacement = .trailing
        self.rowsGrid = rowsGrid

        let stack = NSStackView(views: [headerStack, separator, rowsGrid])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        self.container = stack

        let background = NSVisualEffectView()
        background.material = .popover
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 10
        background.layer?.masksToBounds = true
        background.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: background.topAnchor, constant: 9),
            stack.bottomAnchor.constraint(equalTo: background.bottomAnchor, constant: -9),
        ])

        let panel = NSPanel(contentRect: .zero,
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered,
                            defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        // Above the menu bar and everything else, like a real tooltip.
        panel.level = .popUpMenu
        // Never intercepts the hover it's displaying for, or its own
        // mouseExited would immediately hide it the instant it appears.
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.contentView = background
        self.panel = panel
    }

    var isVisible: Bool { panel.isVisible }

    /// Shows the panel below `buttonScreenFrame` (the status item button's
    /// frame converted to screen coordinates), left-edge anchored to it.
    /// Anchoring by center instead would shift the panel horizontally on
    /// every refresh as the live values change width (e.g. "CPU 8%" vs
    /// "CPU 46%") — a distracting wobble while the values it's meant to be
    /// read are updating. A fixed left edge only ever grows/shrinks to the
    /// right, so the panel itself stays put — except when that would run
    /// past the right edge of the screen, which a status item near the end
    /// of a crowded menu bar does routinely; that case pulls the panel back
    /// onto screen instead.
    func show(near buttonScreenFrame: NSRect, content: StatusItemHoverContent) {
        guard !content.isEmpty else { return }
        apply(content)
        container.layoutSubtreeIfNeeded()
        let fittingSize = container.fittingSize
        let contentSize = NSSize(width: fittingSize.width + 24, height: fittingSize.height + 18)
        var x = buttonScreenFrame.minX
        var y = buttonScreenFrame.minY - contentSize.height - 4
        if let screenFrame = (NSScreen.screens.first { $0.frame.contains(buttonScreenFrame.origin) }
                              ?? NSScreen.main)?.visibleFrame {
            x = min(x, screenFrame.maxX - contentSize.width)
            x = max(x, screenFrame.minX)
            y = max(y, screenFrame.minY)
        }
        panel.setFrame(NSRect(x: x, y: y, width: contentSize.width, height: contentSize.height),
                       display: true)
        panel.orderFront(nil)
    }

    func hide() {
        panel.orderOut(nil)
    }

    private func apply(_ content: StatusItemHoverContent) {
        let headerConfiguration = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
            .applying(NSImage.SymbolConfiguration(paletteColors: [.labelColor]))
        headerIcon.image = NSImage(systemSymbolName: content.symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(headerConfiguration)
        headerLabel.stringValue = content.headline

        // NSGridView.removeRow(at:) drops the row's layout slot but does NOT
        // detach its cells' content views from the grid's subviews — left
        // alone, those views stay frozen at their last-computed frame while
        // the new rows below get laid out over the same space, showing as
        // ghosted double-exposed text.
        while rowsGrid.numberOfRows > 0 {
            let row = rowsGrid.row(at: 0)
            for index in 0..<row.numberOfCells {
                row.cell(at: index).contentView?.removeFromSuperview()
            }
            rowsGrid.removeRow(at: 0)
        }
        separator.isHidden = content.rows.isEmpty

        let rowIconConfiguration = NSImage.SymbolConfiguration(pointSize: 10, weight: .regular)
            .applying(NSImage.SymbolConfiguration(paletteColors: [.secondaryLabelColor]))
        for row in content.rows {
            let icon = NSImageView()
            icon.image = NSImage(systemSymbolName: row.symbolName, accessibilityDescription: nil)?
                .withSymbolConfiguration(rowIconConfiguration)
            icon.translatesAutoresizingMaskIntoConstraints = false
            icon.widthAnchor.constraint(equalToConstant: 12).isActive = true
            icon.heightAnchor.constraint(equalToConstant: 12).isActive = true

            let label = NSTextField(labelWithString: row.label)
            label.font = .systemFont(ofSize: 11, weight: .regular)
            label.textColor = .secondaryLabelColor

            // Tabular digits so a live-updating value doesn't jitter width
            // (and shift the value column) on every refresh tick.
            let value = NSTextField(labelWithString: row.value)
            value.font = .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
            value.textColor = .labelColor
            value.alignment = .right

            rowsGrid.addRow(with: [icon, label, value])
        }
    }
}
