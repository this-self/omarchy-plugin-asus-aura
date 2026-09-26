import QtQuick
import QtTest
import "../../qml/ui"

TestCase {
  id: testCase
  name: "PanelNavigation"
  property var navigation
  Component { id: factory; PanelNavigation {} }
  SignalSpy { id: adjusted; target: testCase.navigation; signalName: "adjusted" }
  SignalSpy { id: activated; target: testCase.navigation; signalName: "activated" }

  function init() {
    navigation = createTemporaryObject(factory, testCase, {sections: [
      {id: "resync", count: 1}, {id: "brightness", slider: true},
      {id: "effect", count: 5}, {id: "hue", slider: true}, {id: "power", count: 4}
    ]})
    navigation.reset()
    adjusted.clear()
    activated.clear()
  }
  function test_first_key_only_reveals_cursor() {
    navigation.move(0, 1)
    verify(navigation.active)
    compare(navigation.section, "brightness")
    navigation.move(0, 1)
    compare(navigation.section, "effect")
    compare(navigation.index, 0)
  }
  function test_slider_arrows_emit_adjustment_without_selection() {
    navigation.select("hue", -1)
    navigation.move(1, 0)
    compare(adjusted.count, 1)
    compare(adjusted.signalArguments[0][0], "hue")
    compare(adjusted.signalArguments[0][1], 1)
    compare(navigation.index, -1)
  }
  function test_options_clamp_and_activate() {
    navigation.select("effect", 0)
    navigation.move(-1, 0)
    compare(navigation.index, 0)
    navigation.move(99, 0)
    compare(navigation.index, 4)
    navigation.activate()
    compare(activated.count, 1)
    compare(activated.signalArguments[0][0], "effect")
    compare(activated.signalArguments[0][1], 4)
  }
  function test_removed_sections_and_shrinking_lists_clamp_focus() {
    navigation.select("power", 3)
    navigation.sections = [{id: "resync", count: 1}, {id: "power", count: 2}]
    compare(navigation.index, 1)
    navigation.sections = [{id: "resync", count: 1}]
    compare(navigation.section, "resync")
    compare(navigation.index, 0)
    navigation.sections = []
    navigation.move(0, 1)
    compare(navigation.index, -1)
  }
  function test_reset_disables_activation_and_starts_at_brightness() {
    navigation.select("power", 2)
    navigation.reset()
    verify(!navigation.active)
    compare(navigation.section, "brightness")
    compare(navigation.index, -1)
    navigation.activate()
    compare(activated.count, 0)
  }
}
