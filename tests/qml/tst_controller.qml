import QtQuick
import QtTest
import "../../qml/app"

TestCase {
  id: testCase
  name: "AuraController"
  property var client
  property var controller
  property var saved

  Component { id: fakeFactory; FakeClient {} }
  Component { id: controllerFactory; AuraController { pollingEnabled: false } }

  function fixture() {
    var request = new XMLHttpRequest()
    request.open("GET", Qt.resolvedUrl("../fixtures/pre2021-global.json"), false)
    request.send()
    return JSON.parse(request.responseText)
  }
  function init() {
    client = createTemporaryObject(fakeFactory, testCase)
    controller = createTemporaryObject(controllerFactory, testCase, {client: client})
    verify(controller !== null)
    saved = fixture()
    client.publish(saved)
  }

  function test_readback_and_optimistic_brightness_are_separate() {
    compare(controller.level, 0)
    verify(controller.setBrightness(2))
    compare(controller.level, 2)
    compare(controller.snapshot.brightness.value, 0)
    compare(saved.brightness.value, 0)
    verify(controller.pending)
    compare(client.requests[0].kind, "brightness")
    client.publish(fixture())
    compare(controller.level, 0)
    verify(!controller.pending)
  }
  function test_rejected_writes_do_not_mutate_editor_or_display() {
    client.acceptRequests = false
    var initial = JSON.stringify(controller.display)
    var hue = controller.colourEditor.hue
    verify(!controller.setBrightness(3))
    verify(!controller.applyHex("#123456"))
    verify(!controller.setChannel("red", 22))
    verify(!controller.setHueSaturation(220, 0.5))
    verify(!controller.setPower(1, "awake", false))
    compare(JSON.stringify(controller.display), initial)
    compare(controller.colourEditor.hue, hue)
  }
  function test_toggle_restores_last_nonzero_level() {
    verify(controller.setBrightness(3))
    verify(controller.toggleBacklight())
    compare(controller.level, 0)
    verify(controller.toggleBacklight())
    compare(controller.level, 3)
  }
  function test_mode_change_locks_parameters_until_readback() {
    verify(controller.selectColourSlot(2))
    verify(controller.selectMode(0))
    compare(controller.colourEditor.effectiveSlot, 1)
    verify(!controller.effectEditable)
    verify(!controller.applyHex("#ff0000"))
    verify(!controller.selectColourSlot(2))
    var next = fixture()
    next.modeId = 0
    next.savedEffect.modeId = 0
    client.publish(next)
    verify(controller.effectEditable)
    verify(controller.applyHex("#ff0000"))
    compare(client.requests[client.requests.length - 1].field, "colour1")
    verify(!controller.setSpeed("Low"))
  }
  function test_selected_slot_is_used_by_hex_and_channel_actions() {
    verify(controller.selectColourSlot(2))
    verify(controller.applyHex("#123456"))
    compare(controller.effect.colour2.red, 18)
    compare(controller.effect.colour1.red, 255)
    compare(client.requests[0].field, "colour2")
    verify(controller.setChannel("green", 300))
    compare(controller.effect.colour2.green, 255)
    compare(saved.savedEffect.colour2.green, 0)
  }
  function test_zone_guard_and_unavailable_state() {
    for (var zone of ["zoned", "unknown"]) {
      var next = fixture()
      next.zoneState = zone
      client.publish(next)
      verify(!controller.effectEditable)
      verify(!controller.applyHex("#ffffff"))
      verify(!controller.setSpeed("High"))
      verify(controller.setBrightness(1))
      verify(controller.setPower(1, "awake", false))
    }
    client.readFailed()
    verify(!controller.available)
    verify(!controller.setBrightness(2))
    verify(!controller.selectMode(1))
    verify(!controller.replaceZones())
  }
  function test_global_conversion_requires_readback() {
    saved.zoneState = "zoned"
    client.publish(saved)
    verify(controller.replaceZones())
    verify(client.modePending)
    verify(!controller.effectEditable)
    compare(client.requests[0].kind, "global")
    client.publish(fixture())
    verify(controller.effectEditable)
  }
  function test_power_update_uses_descriptor_not_raw_rows() {
    verify(controller.setPower(-1, "boot", false))
    verify(!controller.powerControls[0].value)
    verify(saved.powerControls[0].value)
    verify(controller.powerControls[2].value)
    verify(!controller.setPower(1, "boot", false))
    verify(!controller.setPower(1, "shutdown", false))
    verify(!controller.setPower(1, "awake", "false"))
  }
  function test_resync_blocks_other_actions() {
    verify(controller.resync())
    verify(controller.resyncing)
    verify(!controller.setBrightness(2))
    verify(!controller.setSpeed("Low"))
    verify(!controller.applyHex("#ffffff"))
    verify(!controller.selectMode(0))
    verify(!controller.replaceZones())
    verify(!controller.setPower(1, "awake", false))
  }
  function test_unknown_effect_has_no_guessed_parameters() {
    var next = fixture()
    next.modeId = 999
    next.effects.push({id: 999, name: "Mode 999", colourCount: 0, fields: [], speeds: [], directions: []})
    client.publish(next)
    compare(controller.currentMode.name, "Mode 999")
    verify(!controller.applyHex("#ffffff"))
    verify(!controller.setSpeed("High"))
  }
  function test_hue_survives_grey_and_value_is_preserved() {
    verify(controller.applyHex("#808080"))
    verify(controller.setHueSaturation(220, 0))
    compare(controller.colourEditor.hue, 220)
    compare(controller.colourEditor.colour.red, 128)
    verify(controller.setHueSaturation(220, 1))
    compare(Math.max(controller.colourEditor.colour.red, controller.colourEditor.colour.green, controller.colourEditor.colour.blue), 128)
    verify(controller.applyHex("#000000"))
    verify(controller.setHueSaturation(120, 1))
    compare(controller.colourEditor.colour.green, 255)
  }
  function test_invalid_values_never_enqueue() {
    verify(!controller.setBrightness(NaN))
    verify(!controller.setChannel("red", Infinity))
    verify(!controller.setChannel("invalid", 0))
    verify(!controller.applyHex("#fff"))
    verify(!controller.setHueSaturation(NaN, 1))
    verify(!controller.selectMode(999))
    verify(!controller.setDirection("Left"))
    compare(client.requests.length, 0)
  }
  function test_open_refreshes_without_resetting_colour_slot() {
    verify(controller.selectColourSlot(2))
    controller.pollingEnabled = true
    controller.panelOpen = true
    compare(client.refreshCount, 1)
    controller.panelOpen = false
    compare(controller.colourEditor.effectiveSlot, 2)
    controller.panelOpen = true
    compare(client.refreshCount, 2)
  }
}
