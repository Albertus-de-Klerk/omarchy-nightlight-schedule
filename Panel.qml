import QtQuick
import Quickshell
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Schedule.js" as Schedule

// Bar widget + popout for the night light schedule. Live state lives in the
// plugin's service (Service.qml); schedule edits are kept as a draft here and
// only applied when Save is pressed. Colours come from the theme only.
Panel {
  id: root
  moduleName: "albertus.nightlight"
  ipcTarget: "albertus.nightlight"

  readonly property var service: bar && bar.shell ? bar.shell.serviceFor("albertus.nightlight") : null
  readonly property bool ready: !!service && service.stateLoaded
  readonly property bool on: ready && service.enabled
  readonly property int currentTemp: ready ? service.targetTemperature : Schedule.NEUTRAL_TEMP
  readonly property var points: ready ? service.points : []

  readonly property color foreground: bar ? bar.foreground : Commons.Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.4)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  // One height for every control in a schedule row
  readonly property real rowHeight: Style.spacing.controlHeight
  // Column widths of the schedule rows (fit the standard 380 panel width)
  readonly property real timeWidth: Style.space(60)
  readonly property real tempWidth: Style.space(92)
  readonly property real modeWidth: Style.space(84)
  readonly property real stepWidth: Style.space(64)
  readonly property real colGap: Style.space(6)
  // Horizontal inset of the timeline plot, so edge dots aren't clipped;
  // the hour labels use the same inset to line up.
  readonly property real plotInset: Style.space(6)

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  // ---------------- schedule draft ----------------

  property var draft: []
  property bool dirty: false

  function syncDraft() {
    draft = points.map(function(p) { return Object.assign({}, p) })
    dirty = false
  }
  onPointsChanged: if (!dirty) syncDraft()
  // EDIT section is folded away until Edit is pressed; reopening the panel
  // folds it again and drops unsaved edits.
  property bool editing: false
  onOpenedChanged: if (opened) { syncDraft(); editing = false }
  onOnChanged: if (!on) editing = false

  function editDraft(index, patch) {
    if (index < 0 || index >= draft.length) return
    var next = draft.slice()
    next[index] = Object.assign({}, next[index], patch)
    draft = Schedule.normalizePoints(next)
    dirty = true
  }
  function addDraftPoint() {
    draft = Schedule.normalizePoints(draft.concat([Schedule.suggestPoint(draft)]))
    dirty = true
  }
  function removeDraftPoint(index) {
    var next = draft.slice()
    next.splice(index, 1)
    draft = next
    dirty = true
  }
  function save() {
    if (service && dirty) service.setPoints(draft)
    dirty = false
    editing = false
  }

  // ---------------- labels ----------------

  function kelvin(k) { return Commons.I18n.formatNumber(Math.round(k)) + "K" }
  function tempLabel(k) { return k >= Schedule.NEUTRAL_TEMP ? strings.t("now.neutral") : kelvin(k) }
  function clockLabel(ms) { return Qt.formatTime(new Date(ms), "HH:mm") }

  readonly property string statusText: on ? strings.t("status.rhythm") : strings.t("status.suppressor")
  readonly property bool manual: ready && service.overrideActive

  function transitionNext(t) {
    var i = Schedule.TRANSITIONS.indexOf(t)
    return Schedule.TRANSITIONS[(i + 1) % Schedule.TRANSITIONS.length]
  }

  function transitionIcon(t) {
    if (t === "fade") return String.fromCodePoint(0xF0533)   // md-trending_down
    if (t === "steps") return String.fromCodePoint(0xF04CD)  // md-stairs
    return String.fromCodePoint(0xF0054)                     // md-arrow_right
  }

  // ---------------- bar button ----------------

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰔎"
    opacity: root.on || root.manual ? 1.0 : 0.55
    tooltipText: root.on
      ? strings.t("tooltip.on").arg(root.tempLabel(root.currentTemp))
      : strings.t("tooltip.off")
    onPressed: function(b) {
      if (b === Qt.RightButton) { if (root.service) root.service.toggle() }
      else root.toggle()
    }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  // ---------------- popout ----------------

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: panel.loadedContent
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight)

    // Switching straight to another bar icon. The stock overlay catches clicks
    // on the bar strip and forwards them to the icon under the pointer, but a
    // user plugin is only told about its own icons, so the click on any other
    // icon was swallowed and the panel just closed. Leave the bar strip out of
    // this overlay instead: the click reaches the real bar, that icon opens
    // its panel, and the bar's popout hand-off closes this one.
    mask: Region {
      width: panel.screenW
      height: panel.screenH
      Region {
        intersection: Intersection.Subtract
        x: panel.barPos === "right" ? panel.screenW - panel.barThickness : 0
        y: panel.barPos === "bottom" ? panel.screenH - panel.barThickness : 0
        width: panel.barPos === "left" || panel.barPos === "right" ? panel.barThickness : panel.screenW
        height: panel.barPos === "left" || panel.barPos === "right" ? panel.screenH : panel.barThickness
      }
    }

    content: PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      implicitHeight: column.implicitHeight
      // Let text/number fields receive keys while they are being edited
      blocked: {
        var f = keyCatcher.Window.activeFocusItem
        return !!f && f.cursorPosition !== undefined
      }
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(14)

        // ---------- Hero ----------
        Item {
          width: parent.width
          implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight, powerSwitch.implicitHeight)

          Text {
            id: heroIcon
            textFormat: Text.PlainText
            text: "󰔎"
            color: root.foreground
            opacity: root.on || root.manual ? 1.0 : 0.5
            font.family: root.fontFamily
            font.pixelSize: Style.font.display
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            Behavior on color { ColorAnimation { duration: Style.duration(200) } }
          }

          Column {
            id: heroLabels
            anchors.left: heroIcon.right
            anchors.leftMargin: Style.space(14)
            anchors.right: powerSwitch.left
            anchors.rightMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              textFormat: Text.PlainText
              text: strings.t("title")
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
              elide: Text.ElideRight
              width: parent.width
            }

            Text {
              textFormat: Text.PlainText
              text: root.statusText.toUpperCase()
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.2
              elide: Text.ElideRight
              width: parent.width
            }
          }

          ToggleSwitch {
            id: powerSwitch
            checked: root.on
            foreground: root.foreground
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            onToggled: if (root.service) root.service.toggle()

            PanelToolTip {
              visible: powerSwitch.containsMouse
              text: root.on ? strings.t("switch.on") : strings.t("switch.off")
            }
          }
        }

        // ---------- TINT (always shown) ----------
          PanelSeparator { foreground: root.foreground }

          Column {
            width: parent.width
            spacing: Style.space(10)

            Item {
              width: parent.width
              implicitHeight: nowHeader.implicitHeight

              PanelSectionHeader {
                id: nowHeader
                text: strings.t("section.now")
                foreground: root.foreground
                fontFamily: root.fontFamily
                anchors.left: parent.left
              }

              Text {
                textFormat: Text.PlainText
                anchors.right: parent.right
                anchors.verticalCenter: nowHeader.verticalCenter
                text: root.tempLabel(slider.dragging ? slider.liveValue : root.currentTemp)
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.bold: true
              }
            }

            PanelSlider {
              id: slider
              width: parent.width
              bar: root.bar
              minimum: Schedule.MIN_TEMP
              maximum: Schedule.MAX_TEMP
              step: 50
              integer: true
              value: root.currentTemp
              onMoved: function(v) { if (root.service) root.service.setOverride(v) }
              onReleased: function(v) { if (root.service) root.service.setOverride(v) }
            }

            Item {
              width: parent.width
              implicitHeight: Math.max(nowInfo.implicitHeight, resumeButton.visible ? resumeButton.implicitHeight : 0)

              Text {
                id: nowInfo
                textFormat: Text.PlainText
                anchors.left: parent.left
                anchors.right: resumeButton.visible ? resumeButton.left : parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: !root.on ? strings.t("status.off")
                  : (root.manual ? strings.t("now.manual").arg(root.clockLabel(root.service.override.until))
                                 : strings.t("now.schedule"))
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                elide: Text.ElideRight
              }

              Button {
                id: resumeButton
                visible: root.manual && root.on
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                height: root.rowHeight
                text: strings.t("now.resume")
                iconText: "󰑐"
                fontSize: Style.font.bodySmall
                foreground: root.foreground
                fontFamily: root.fontFamily
                bordered: true
                onClicked: root.service.clearOverride()
              }
            }
          }

        // Everything below the Schedule ON/OFF line only exists while the
        // schedule is on; when it is off the panel collapses, like Bluetooth/Wi-Fi.
        Column {
          width: parent.width
          spacing: Style.space(14)
          visible: root.on

          // ---------- 24h timeline ----------
          PanelSeparator { foreground: root.foreground }

          Column {
            width: parent.width
            spacing: Style.space(6)

            PanelSectionHeader {
              text: strings.t("section.timeline")
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Timeline {
              width: parent.width
              height: Style.space(64)
            }

            Item {
              width: parent.width
              implicitHeight: hourMetrics.height
              Text { id: hourMetrics; visible: false; text: "00"; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
              Repeater {
                model: [0, 6, 12, 18, 24]
                Text {
                  required property var modelData
                  textFormat: Text.PlainText
                  text: (modelData < 10 ? "0" : "") + modelData
                  x: Math.max(0, Math.min(parent.width - width,
                       root.plotInset + (parent.width - 2 * root.plotInset) * modelData / 24 - width / 2))
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }
            }
          }

          // ---------- EDIT (unfolds from the Edit button) ----------
          PanelSeparator { foreground: root.foreground; visible: root.editing }

          Column {
            width: parent.width
            spacing: Style.space(8)
            visible: root.editing

            PanelSectionHeader {
              text: strings.t("section.edit")
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Row {
              visible: root.draft.length > 0
              width: parent.width
              spacing: root.colGap
              Heading { width: root.timeWidth; text: strings.t("schedule.time") }
              Heading { width: root.tempWidth; text: strings.t("schedule.temp") }
              Heading { width: root.modeWidth; text: strings.t("schedule.arrive") }
              Heading { width: root.stepWidth; text: strings.t("schedule.every") }
            }

            Text {
              visible: root.draft.length === 0
              textFormat: Text.PlainText
              text: strings.t("schedule.empty")
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              width: parent.width
              wrapMode: Text.WordWrap
            }

            Flickable {
              id: rowsFlick
              width: parent.width
              height: Math.min(rowsColumn.implicitHeight, (root.rowHeight + rowsColumn.spacing) * 6)
              contentHeight: rowsColumn.implicitHeight
              clip: contentHeight > height
              interactive: contentHeight > height
              boundsBehavior: Flickable.StopAtBounds

              Column {
                id: rowsColumn
                width: rowsFlick.width
                spacing: Style.space(6)

                Repeater {
                  model: root.draft
                  delegate: PointRow {}
                }
              }
            }

            Button {
              height: root.rowHeight
              text: strings.t("schedule.add")
              iconText: "󰐕"
              fontSize: Style.font.bodySmall
              foreground: root.foreground
              fontFamily: root.fontFamily
              bordered: true
              onClicked: root.addDraftPoint()
            }
          }

          // ---------- Edit / Save (same spot) ----------
          PanelSeparator { foreground: root.foreground }

          Item {
            width: parent.width
            implicitHeight: saveButton.implicitHeight

            Text {
              textFormat: Text.PlainText
              anchors.left: parent.left
              anchors.right: saveButton.left
              anchors.rightMargin: Style.space(10)
              anchors.verticalCenter: parent.verticalCenter
              text: root.editing && root.dirty ? strings.t("schedule.unsaved") : ""
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              elide: Text.ElideRight
            }

            Button {
              id: saveButton
              anchors.right: parent.right
              height: root.rowHeight
              // Edit unfolds the EDIT section; the same button then saves
              // (and folds it away again).
              text: root.editing ? strings.t("schedule.save") : strings.t("schedule.edit")
              iconText: root.editing ? "󰆓" : "󰏫"
              fontSize: Style.font.bodySmall
              foreground: root.foreground
              fontFamily: root.fontFamily
              bordered: true
              active: root.editing && root.dirty
              onClicked: {
                if (root.editing) root.save()
                else { root.syncDraft(); root.editing = true }
              }
            }
          }
        }
      }
    }
  }

  // ---------------- components ----------------

  component Heading: Text {
    textFormat: Text.PlainText
    color: root.dim
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    elide: Text.ElideRight
  }

  // One schedule point: time · temperature · how to arrive · step size · remove
  component PointRow: Row {
    id: row
    required property var modelData
    required property int index
    spacing: root.colGap
    height: root.rowHeight

    TextField {
      id: timeField
      width: root.timeWidth
      height: root.rowHeight
      anchors.verticalCenter: parent.verticalCenter
      verticalPadding: 0
      text: row.modelData.time
      foreground: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      horizontalAlignment: TextInput.AlignHCenter
      verticalAlignment: TextInput.AlignVCenter
      inputMethodHints: Qt.ImhTime
      maximumLength: 5
      placeholderText: "HH:MM"
      property bool invalid: false
      color: invalid ? Commons.Color.urgent : root.foreground
      onTextEdited: invalid = Schedule.parseTime(text) < 0
      onEditingFinished: {
        var m = Schedule.parseTime(text)
        if (m < 0) { text = row.modelData.time; invalid = false; return }
        var t = Schedule.formatTime(m)
        if (t !== row.modelData.time) root.editDraft(row.index, { time: t })
        else text = t
      }
      PanelToolTip { visible: timeField.invalid; text: strings.t("schedule.invalidTime") }
    }

    NumberField {
      anchors.verticalCenter: parent.verticalCenter
      fieldWidth: root.tempWidth
      field.height: root.rowHeight
      from: Schedule.MIN_TEMP
      to: Schedule.MAX_TEMP
      stepSize: 50
      value: row.modelData.temp
      foreground: root.foreground
      fontFamily: root.fontFamily
      fontSize: Style.font.bodySmall
      onModified: function(v) { root.editDraft(row.index, { temp: v }) }
    }

    Button {
      width: root.modeWidth
      height: root.rowHeight
      anchors.verticalCenter: parent.verticalCenter
      text: strings.t("transition." + row.modelData.transition)
      iconText: root.transitionIcon(row.modelData.transition)
      fontSize: Style.font.bodySmall
      foreground: root.foreground
      fontFamily: root.fontFamily
      bordered: true
      tooltipText: strings.t("transition." + row.modelData.transition + ".tip")
      onClicked: root.editDraft(row.index, { transition: root.transitionNext(row.modelData.transition) })
    }

    Item {
      width: root.stepWidth
      height: root.rowHeight

      NumberField {
        visible: row.modelData.transition === "steps"
        anchors.verticalCenter: parent.verticalCenter
        fieldWidth: root.stepWidth
        field.height: root.rowHeight
        from: 1
        to: 240
        stepSize: 5
        value: row.modelData.stepMinutes
        foreground: root.foreground
        fontFamily: root.fontFamily
        fontSize: Style.font.bodySmall
        onModified: function(v) { root.editDraft(row.index, { stepMinutes: v }) }
      }
    }

    PanelActionButton {
      anchors.verticalCenter: parent.verticalCenter
      iconText: "󰆴"
      foreground: root.foreground
      fontFamily: root.fontFamily
      tooltipText: strings.t("schedule.remove")
      onClicked: root.removeDraftPoint(row.index)
    }
  }

  // 24h curve in theme colours. Layers, bottom to top: track, area fill
  // (fades from strong at the warm top to faint at the bottom), curve,
  // "now" marker, schedule dots. The plot is inset by the dot radius on every
  // side so dots on the edges are never clipped. Shows the draft, so edits
  // preview before they are saved.
  component Timeline: Canvas {
    id: canvas
    renderStrategy: Canvas.Cooperative
    readonly property var pts: root.draft
    readonly property double nowMs: root.ready ? root.service.now : 0
    readonly property color fg: root.foreground
    readonly property real dotRadius: Style.space(3.5)
    onPtsChanged: requestPaint()
    onFgChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    property int minuteKey: Math.floor(nowMs / 60000)
    onMinuteKeyChanged: requestPaint()

    onPaint: {
      var ctx = getContext("2d")
      var w = width, h = height
      ctx.reset()

      var padX = root.plotInset
      var padY = dotRadius + 2
      var left = padX, right = w - padX
      var top = padY, bottom = h - padY
      var span = Schedule.MAX_TEMP - Schedule.MIN_TEMP
      function xFor(minutes) { return left + minutes / 1440 * (right - left) }
      function yFor(k) { return bottom - (Schedule.MAX_TEMP - k) / span * (bottom - top) }
      function rgba(a) { return Qt.rgba(fg.r, fg.g, fg.b, a) }

      // 1. track
      ctx.fillStyle = rgba(0.06)
      ctx.fillRect(0, 0, w, h)

      var samples = Math.max(96, Math.round(right - left))
      var temps = Schedule.curve(pts, samples)
      function px(i) { return left + i / samples * (right - left) }

      // 2. area under the curve, one path (no seams)
      ctx.beginPath()
      ctx.moveTo(px(0), bottom)
      for (var i = 0; i <= samples; i++) ctx.lineTo(px(i), yFor(temps[i]))
      ctx.lineTo(px(samples), bottom)
      ctx.closePath()
      var grad = ctx.createLinearGradient(0, top, 0, bottom)
      grad.addColorStop(0, rgba(0.45))
      grad.addColorStop(1, rgba(0.08))
      ctx.fillStyle = grad
      ctx.fill()

      // 3. curve
      ctx.strokeStyle = rgba(0.9)
      ctx.lineWidth = 1.5
      ctx.lineJoin = "round"
      ctx.beginPath()
      for (var j = 0; j <= samples; j++) {
        if (j === 0) ctx.moveTo(px(j), yFor(temps[j])); else ctx.lineTo(px(j), yFor(temps[j]))
      }
      ctx.stroke()

      // 4. now marker
      if (nowMs > 0) {
        var nx = Math.round(xFor(Schedule.minutesOfDay(new Date(nowMs)))) + 0.5
        ctx.strokeStyle = rgba(0.7)
        ctx.lineWidth = 1
        ctx.setLineDash([3, 3])
        ctx.beginPath()
        ctx.moveTo(nx, 0)
        ctx.lineTo(nx, h)
        ctx.stroke()
        ctx.setLineDash([])
      }

      // 5. schedule dots, ringed in the panel background so they sit cleanly
      //    on top of the curve and the now marker
      var bg = Commons.Color.popups.background
      for (var p = 0; p < pts.length; p++) {
        var dx = xFor(Schedule.parseTime(pts[p].time)), dy = yFor(pts[p].temp)
        ctx.beginPath()
        ctx.arc(dx, dy, dotRadius + 1.5, 0, Math.PI * 2)
        ctx.fillStyle = bg
        ctx.fill()
        ctx.beginPath()
        ctx.arc(dx, dy, dotRadius, 0, Math.PI * 2)
        ctx.fillStyle = rgba(1)
        ctx.fill()
      }
    }
  }
}
