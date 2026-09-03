/*
===========================================================================

Doom 3 BFG Edition GPL Source Code
Copyright (C) 1993-2012 id Software LLC, a ZeniMax Media company.

This file is part of the Doom 3 BFG Edition Source Code ("Doom 3 BFG Edition Source Code").

===========================================================================
*/

#pragma once

class idCmdArgs;

// Optional local compatibility layer for explicitly loading a user-supplied
// ReShade add-on runtime before the D3D12 device is created. The default path
// remains completely disabled and has no binary dependency on ReShade.
bool R_NeuralCompatibilityInitialize();
void R_NeuralCompatibilityStatus_f( const idCmdArgs& args );
