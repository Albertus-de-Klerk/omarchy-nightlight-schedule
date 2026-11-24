// Run: node tests/schedule.test.js
const assert = require("assert")
const S = require("../Schedule.js")

const def = S.defaultConfig().points
const at = (pts, hhmm) => S.temperatureAt(pts, S.parseTime(hhmm))
let n = 0
const eq = (a, b, msg) => { assert.strictEqual(a, b, msg || `expected ${b}, got ${a}`); n++ }

// Default schedule matches the previous script: 05-17 neutral, fade 17->22, 1500 overnight
eq(at(def, "04:59"), 1500, "night before 05:00")
eq(at(def, "05:00"), 6500, "05:00 jump to neutral")
eq(at(def, "12:00"), 6500)
eq(at(def, "17:00"), 6500)
eq(at(def, "17:15"), 6250, "250K per 15 min")
eq(at(def, "19:30"), 4000)
eq(at(def, "21:45"), 1750)
eq(at(def, "22:00"), 1500)
eq(at(def, "23:59"), 1500)
eq(at(def, "00:00"), 1500)
eq(S.temperatureAt(def, 17 * 60 + 0.06), 6499, "1K resolution after 3.6s")

// Steps
const steps = S.normalizePoints([
  { time: "18:00", temp: 6500 },
  { time: "19:00", temp: 4500, transition: "steps", stepMinutes: 15 },
])
eq(at(steps, "18:00"), 6500)
eq(at(steps, "18:14"), 6500)
eq(at(steps, "18:15"), 6000)
eq(at(steps, "18:59"), 5000)
eq(at(steps, "19:00"), 4500)
eq(at(steps, "03:00"), 4500, "fixed back to 6500 only at 18:00")

// Wrap-around fade across midnight
const wrap = S.normalizePoints([
  { time: "23:00", temp: 3000, transition: "fixed" },
  { time: "01:00", temp: 1000, transition: "fade" },
  { time: "08:00", temp: 6500, transition: "fixed" },
])
eq(at(wrap, "00:00"), 2000, "midpoint of fade across midnight")
eq(at(wrap, "07:59"), 1000)
eq(at(wrap, "08:00"), 6500)
eq(at(wrap, "22:59"), 6500)

// Parsing / normalising
eq(S.parseTime("7:05"), 425)
eq(S.parseTime("0705"), 425)
eq(S.parseTime("7"), 420)
eq(S.parseTime("24:00"), -1)
eq(S.parseTime("ab"), -1)
eq(S.clampTemp(200), 1000)
eq(S.clampTemp(9000), 6500)
const norm = S.normalizePoints([{ time: "9:00", temp: 3000 }, { time: "bad" }, { time: "09:00", temp: 2000 }, { time: "08:00", temp: 4000 }])
eq(norm.length, 2, "dedupe + drop invalid")
eq(norm[0].time, "08:00", "sorted")
eq(norm[1].temp, 2000, "last wins")
eq(S.normalizeConfig(null).enabled, true)
eq(S.normalizeConfig({ enabled: false, points: [] }).points.length, 0)
eq(S.temperatureAt([], 600), 6500, "empty schedule = neutral")

// Upcoming / next point
const up = S.upcoming(def, S.parseTime("18:00"))
eq(up.time, "22:00"); eq(up.changing, true)
eq(S.upcoming(def, S.parseTime("12:00")).changing, false)
const now = new Date(2026, 10, 8, 23, 0).getTime()
eq(new Date(S.nextPointMs(def, now)).getHours(), 5, "override ends at next point (05:00 tomorrow)")
eq(new Date(S.nextPointMs(def, now)).getDate(), 9)

// Next change while holding: at 12:00 the fade starting at 17:00
const nc = S.nextChange(def, S.parseTime("12:00"))
eq(nc.time, "17:00"); eq(nc.temp, 6483)
eq(S.nextChange(def, S.parseTime("23:00")).time, "05:00")

// Override with no end (schedule off) survives normalising
eq(S.normalizeConfig({ enabled: false, points: [], override: { temp: 3000, until: null } }).override.until, null)
eq(S.normalizeConfig({ override: { temp: 3000, until: "x" } }).override, null)

// Suggest
const sug = S.suggestPoint(def)
eq(sug.time, "11:00", "middle of the longest gap (05:00-17:00)")

console.log(`ok - ${n} assertions passed`)
