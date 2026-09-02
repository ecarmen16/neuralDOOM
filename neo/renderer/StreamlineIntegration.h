/*
===========================================================================

Doom 3 BFG Edition GPL Source Code
Copyright (C) 1993-2012 id Software LLC, a ZeniMax Media company.

This file is part of the Doom 3 BFG Edition Source Code ("Doom 3 BFG Edition Source Code").

===========================================================================
*/

#pragma once

class idCmdArgs;

// These entry points are harmless stubs when the optional SDK is disabled.
bool R_StreamlineInitialize();
bool R_StreamlineSetD3DDevice( void* nativeDevice );
void R_StreamlineShutdown();
bool R_StreamlineIsInitialized();
bool R_StreamlineIsDLSSRequested();
void R_StreamlineStatus_f( const idCmdArgs& args );

