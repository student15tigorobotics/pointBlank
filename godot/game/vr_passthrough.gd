# Copyright (C) 2026 tigo.robotics@gmail.com
# This file is part of PointBlank Swarm.
#
# PointBlank Swarm is free software: you can redistribute it and/or modify it under the
# terms of the GNU General Public License as published by the Free Software Foundation,
# either version 3 of the License, or (at your option) any later version.
#
# It is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; see the
# GNU General Public License for more details. See the LICENSE file in the repository root.

class_name VrPassthrough
extends RefCounted
## HTC passthrough through godot_openxr_vendors (v3.0.0 or later). Static helpers only.
## Unverified on hardware: whether the runtime actually shows the HTC layer must be checked on the headset.


## True when the godot_openxr_vendors HTC passthrough class is registered.
static func plugin_installed() -> bool:
	return ClassDB.class_exists("OpenXRHtcPassthroughExtension")


## True when the XR runtime can blend the game over the real room (alpha blend).
static func alpha_supported(xr: XRInterface) -> bool:
	if xr == null:
		return false
	return xr.get_supported_environment_blend_modes().has(XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND)


## On: alpha blend, transparent viewport, clear-colour background. Off: opaque blend, opaque viewport, solid background.
## Returns true if the blend mode was applied. Nothing changes when it returns false.
static func set_enabled(xr: XRInterface, viewport: Viewport, env: Environment, on: bool) -> bool:
	if xr == null:
		return false
	if on and not alpha_supported(xr):
		return false
	xr.environment_blend_mode = XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND if on else XRInterface.XR_ENV_BLEND_MODE_OPAQUE
	if viewport != null:
		viewport.transparent_bg = on
	if env != null:
		env.background_mode = Environment.BG_CLEAR_COLOR if on else Environment.BG_COLOR
	return true
