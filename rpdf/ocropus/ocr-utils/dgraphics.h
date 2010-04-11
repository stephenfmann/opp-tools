// -*- C++ -*-

#ifndef dgraphics_util_h__
#define dgraphics_util_h__

// Copyright 2006-2007 Deutsches Forschungszentrum fuer Kuenstliche Intelligenz 
// or its licensors, as applicable.
// 
// You may not use this file except under the terms of the accompanying license.
// 
// Licensed under the Apache License, Version 2.0 (the "License"); you
// may not use this file except in compliance with the License. You may
// obtain a copy of the License at http:  www.apache.org/licenses/LICENSE-2.0
// 
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
// 
// Project: 
// File: 
// Purpose: 
// Responsible: tmb
// Reviewer: 
// Primary Repository: 
// Web Sites: www.iupr.org, www.dfki.de

/// \file dgraphics.h
/// \brief Graphical output for Lua scripts

#include "colib.h"

namespace ocropus {
    void dinit(int w,int h);
    void dclear(int rgb);
    template <class T>
    void dshow(colib::narray<T> &data,const char *spec="",double angle=90,int smooth=1,int rgb=0);
   
    template <class T>
    void dshown(colib::narray<T> &data,const char *spec="",double angle=90,int smooth=1,int rgb=0);
    void dshowr(colib::intarray &data,const char *spec="",double angle=90,int smooth=1,int rgb=0);
    void dwait();
} 


#endif /* dgraphics_util_h__ */
