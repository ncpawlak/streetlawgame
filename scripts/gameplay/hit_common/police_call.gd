class_name PoliceCall
extends Node
## The police-call countdown for a hit. Neighbours (an unoccupied break-in), gunshots and witnesses
## start a countdown; an alarm (camera or alarmed door) calls the police immediately. When the
## countdown reaches zero, or on an immediate call, [signal police_called] fires and a
## [PoliceResponse] dispatches cops.

signal countdown_started(seconds: float, reason: StringName)
## A hidden (silent alarm) countdown became visible near the end.
signal countdown_revealed
signal police_called(reason: StringName)
signal reset_done

enum State { IDLE, COUNTDOWN, CALLED }

const REASON_NEIGHBOURS := &"neighbours"
const REASON_GUNSHOT := &"gunshot"
const REASON_EXPLOSION := &"explosion"
const REASON_ALARM := &"alarm"
const REASON_CAMERA := &"camera"
const REASON_SILENT_ALARM := &"silent_alarm"
const REASON_WITNESS := &"witness"
const REASON_DOG := &"dog"

const REASON_TEXT := {
	&"neighbours": "The neighbours noticed the break-in",
	&"gunshot": "Shots fired - the neighbours are calling the cops",
	&"explosion": "An explosion - the neighbours are calling the cops",
	&"alarm": "ALARM! The police have been called",
	&"camera": "Caught on camera! The police have been called",
	&"silent_alarm": "Silent alarm",
	&"witness": "A witness is calling the cops",
	&"dog": "A dog is barking its head off - the neighbours are looking",
}

## Default countdown when no time is given.
@export var countdown_seconds := 45.0
## Noises (gunshots, explosions) within this radius of [member listen_center] start the countdown.
@export var hearing_radius := 40.0
## Where the neighbours are listening from (the house / shop). Null hears everywhere.
@export var listen_center: Node3D
@export var listen_gunshots := true
## A hidden countdown turns visible with this many seconds left.
@export var reveal_at := 10.0
## Multiplies every countdown length (heat makes it shorter, a crew lookout longer).
var countdown_scale := 1.0

var state := State.IDLE
var time_left := 0.0
var hidden := false
## Why the current countdown/call started.
var reason: StringName = &""


func _ready() -> void:
	EventBus.gunshot.connect(func(at: Vector3, _shooter: Node) -> void: report_noise(at, REASON_GUNSHOT))
	EventBus.explosion.connect(func(at: Vector3, _radius: float) -> void: report_noise(at, REASON_EXPLOSION))


func _process(delta: float) -> void:
	if state != State.COUNTDOWN:
		return
	time_left = maxf(0.0, time_left - delta)
	if hidden and time_left <= reveal_at:
		hidden = false
		countdown_revealed.emit()
	if time_left <= 0.0:
		_call(reason)


func is_counting() -> bool:
	return state == State.COUNTDOWN


func is_called() -> bool:
	return state == State.CALLED


## Counting down or already called.
func is_active() -> bool:
	return state != State.IDLE


## Starts the countdown. If one is already running, the shorter remaining time wins. No effect once
## the police have been called. [param seconds] < 0 uses [member countdown_seconds].
func start_countdown(why: StringName, seconds := -1.0, secret := false) -> void:
	if state == State.CALLED:
		return
	var duration := (countdown_seconds if seconds < 0.0 else seconds) * countdown_scale
	if state == State.COUNTDOWN:
		if duration < time_left:
			time_left = duration
			reason = why
		if not secret and hidden:
			hidden = false
			countdown_revealed.emit()
		return
	state = State.COUNTDOWN
	time_left = duration
	hidden = secret
	reason = why
	if not secret:
		EventBus.notify.emit("%s - police in %d s" % [REASON_TEXT.get(why, String(why)), ceili(duration)])
	countdown_started.emit(duration, why)
	if duration <= 0.0:
		_call(why)


## Calls the police right now (a tripped alarm or camera).
func call_now(why: StringName) -> void:
	if state == State.CALLED:
		return
	reason = why
	_call(why)


## A loud noise at [param at]; starts the countdown if the neighbours can hear it.
func report_noise(at: Vector3, why: StringName = REASON_GUNSHOT) -> void:
	if not listen_gunshots or state != State.IDLE or not is_inside_tree():
		return
	if listen_center != null and is_instance_valid(listen_center) and listen_center.global_position.distance_to(at) > hearing_radius:
		return
	start_countdown(why)


## Makes a hidden (silent alarm) countdown visible early, e.g. a crew lookout spotting it.
func reveal() -> void:
	if state == State.COUNTDOWN and hidden:
		hidden = false
		countdown_revealed.emit()


func reset() -> void:
	state = State.IDLE
	time_left = 0.0
	hidden = false
	reason = &""
	reset_done.emit()


func status_text() -> String:
	match state:
		State.COUNTDOWN:
			return "" if hidden else "POLICE IN %d" % ceili(time_left)
		State.CALLED:
			return "POLICE CALLED"
	return ""


func _call(why: StringName) -> void:
	state = State.CALLED
	time_left = 0.0
	hidden = false
	if why == REASON_ALARM or why == REASON_CAMERA:
		EventBus.notify.emit(REASON_TEXT[why])
	else:
		EventBus.notify.emit("The police are on their way!")
	police_called.emit(why)
