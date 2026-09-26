import QtQuick

// Cursor state only. Sections describe {id, count, slider}; actions leave via
// signals and are wired to the same intents as mouse interaction in the popup.
QtObject {
  id: root
  property var sections: []
  property bool active: false
  property string section: "brightness"
  property int index: -1
  signal adjusted(string section, int delta)
  signal activated(string section, int index)

  onSectionsChanged: clamp()

  function current() {
    return root.sections.find(function(s) { return s.id === root.section }) || null
  }
  function firstIndex(section) { return section.slider ? -1 : 0 }
  function reset() {
    root.active = false
    root.section = "brightness"
    root.index = -1
    root.clamp()
  }
  function select(section, index) {
    root.active = true
    root.section = section
    root.index = index
    root.clamp()
  }
  function clamp() {
    if (!root.sections.length) { root.index = -1; return }
    var current = root.current()
    if (!current) {
      current = root.sections[0]
      root.section = current.id
      root.index = root.firstIndex(current)
    }
    root.index = current.slider ? -1 : Math.max(0, Math.min(current.count - 1, root.index))
  }
  function move(dx, dy) {
    if (!root.active) { root.active = true; return }
    if (!root.sections.length) return
    if (dy !== 0) {
      var position = root.sections.findIndex(function(s) { return s.id === root.section })
      var next = position + dy
      if (next < 0 || next >= root.sections.length) return
      root.section = root.sections[next].id
      root.index = root.firstIndex(root.sections[next])
    } else if (dx !== 0) {
      var current = root.current()
      if (!current) return
      if (current.slider) root.adjusted(root.section, dx)
      else root.index = Math.max(0, Math.min(current.count - 1, root.index + dx))
    }
  }
  function activate() { if (root.active) root.activated(root.section, root.index) }
}
