# What is running today, and what is running on Saturday.
#
# Every event in this game is a relative timer: the chain starts when a phone
# happens to roll one in and runs for a span from that moment. That is a fine
# way to run a rotation and no way at all to run a calendar -- "the chain starts
# on Saturday" cannot be said in main.gd, with or without a new binary.
#
# This file is the other way of answering "is an event on". It does not replace
# the rotation: it pre-empts it for a window and hands it back afterwards. See
# the migration behind it for the table.
#
# THE SAME ONE RULE flags.gd has: an empty answer is today's game. No rows, no
# network, an unapplied migration, a kind this build has never heard of -- every
# one of them leaves main.gd rolling chains in on its own clock exactly as it
# has since the chain existed.
#
# NO CLOCK IS TRUSTED HERE, and that is the design rather than a precaution.
# `_now()` in main.gd is a high-water mark because the device clock is something
# a player can move from the Settings app, and `_trusted_now()` falls back to it
# for anybody who has not signed in. So the server is never asked WHEN an event
# is; it is asked HOW LONG until one starts and how long until it ends, and it
# does that arithmetic against a clock nobody can move. What arrives here is
# seconds, and seconds are the one thing this device can count honestly.
extends Node

const APP := "loot-lagoon"

# How far ahead to ask. Longer than any gap between two launches, short enough
# that a year of planned events is not sent to a phone deciding what to do in
# the next ten minutes.
const HORIZON_HOURS := 72

# {kind, payload, starts_ms, ends_ms} -- the two spans converted to this
# process's own monotonic clock at the moment the answer landed.
var _events: Array = []
var _fetched := false


# NOTHING IS CACHED TO DISK, and this is the one place this file deliberately
# differs from flags.gd.
#
# A kill switch is cached because it must apply on a cold start before the
# network answers -- a switch that needs a round trip lets the broken feature
# run for the first seconds of every launch. A calendar has the opposite shape:
# what it holds is a COUNTDOWN, and a countdown written to disk is wrong by
# however long the app was shut. Restoring it would mean trusting the device
# clock to measure that gap, which is the exact thing the paragraph above says
# is not available here.
#
# So an offline cold start runs the rotation. The cost of that is one scheduled
# event missing its start for a player with no signal, and the thing that makes
# it small is that a chain ALREADY RUNNING is held in the save by main.gd with
# its own deadline -- so an event that started while there was a network keeps
# running without one. Only beginning one needs the server.
func refresh() -> void:
	if not Cloud.configured():
		return
	# Stamped BEFORE the request, so the round trip is counted as time that has
	# already passed. Same reasoning as Cloud.refresh_time: erring by the
	# latency puts the anchor slightly behind, which ends an event a moment
	# early rather than a moment late.
	var at := Time.get_ticks_msec()
	Cloud.app_events(APP, Flags.build_number(), Flags.platform_tag(), HORIZON_HOURS,
		func(list: Array) -> void:
			# An empty list is a real answer here, unlike in flags.gd. There the
			# empty case is indistinguishable from a failure and discarding it
			# is what keeps a kill switch live; here the failure path already
			# returns [] and so does "nothing is scheduled", and treating the
			# two the same is correct -- both mean "run the rotation". Keeping a
			# stale calendar instead would run an event that has been cancelled.
			var fresh := []
			for row in list:
				if typeof(row) != TYPE_DICTIONARY:
					continue
				var d: Dictionary = row
				var kind := str(d.get("kind", ""))
				if kind == "":
					continue
				# Defensive: a row whose spans are not numbers is a row this
				# build cannot act on, and acting on 0 would start an event
				# that is instantly over.
				var s = d.get("starts_in")
				var e = d.get("ends_in")
				if not (typeof(s) in [TYPE_INT, TYPE_FLOAT]) \
						or not (typeof(e) in [TYPE_INT, TYPE_FLOAT]):
					continue
				if float(e) <= float(s):
					continue
				var payload = d.get("payload", {})
				fresh.append({
					"kind": kind,
					"payload": payload if typeof(payload) == TYPE_DICTIONARY else {},
					"starts_ms": at + int(float(s) * 1000.0),
					"ends_ms": at + int(float(e) * 1000.0),
				})
			_events = fresh
			_fetched = true
	)


# The event of this kind that is running right now, or {} if none is.
#
# The FIRST one, and the server already sorted them by when they happen -- so
# two overlapping rows of the same kind resolve to the one that started earlier
# rather than to whichever the planner felt like. Overlapping rows are a
# scheduling mistake rather than a feature, and the only thing that matters is
# that the mistake resolves the same way on every phone.
func live(kind: String) -> Dictionary:
	var now := Time.get_ticks_msec()
	for ev in _events:
		var d: Dictionary = ev
		if str(d.get("kind", "")) != kind:
			continue
		if now >= int(d.get("starts_ms", 0)) and now < int(d.get("ends_ms", 0)):
			return d
	return {}


# How long that event has left, in seconds. Never negative.
#
# ONLY MEANINGFUL AT THE MOMENT AN EVENT IS STARTED, which is the only way
# main.gd uses it. Once a chain is running its deadline lives in the save and is
# counted down against main.gd's own clock -- so a phone that was suspended for
# six hours resumes a chain with the right time left on it, whether or not
# get_ticks_msec counted the sleep. If this were the running countdown instead,
# a platform whose monotonic clock pauses during suspension would hand a player
# back an event that had not aged.
func seconds_left(ev: Dictionary) -> float:
	return maxf(0.0, float(int(ev.get("ends_ms", 0)) - Time.get_ticks_msec()) / 1000.0)


# For the harness and the Options page's diagnostic line only. No gameplay
# decision may depend on it: "we have not heard yet" and "nothing is scheduled"
# must behave the same, because they do.
func fetched() -> bool:
	return _fetched


func all() -> Array:
	return _events.duplicate(true)
