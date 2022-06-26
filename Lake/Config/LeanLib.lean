/-
Copyright (c) 2022 Mac Malone. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Mac Malone
-/
import Lake.Config.Package

namespace Lake
open Lean System

/-- A Lean library -- its package plus its configuration. -/
structure LeanLib where
  /-- The package the library belongs to. -/
  pkg : Package
   /-- The library's user-defined configuration. -/
  config : LeanLibConfig
  deriving Inhabited

/-- The Lean library built into the package. -/
@[inline] def Package.builtinLib (self : Package) : LeanLib :=
  ⟨self, self.builtinLibConfig⟩

/-- Try to find a Lean library in the package with the given name. -/
@[inline] def Package.findLeanLib? (name : Name) (self : Package) : Option LeanLib :=
  self.leanLibConfigs.find? name |>.map (⟨self, ·⟩)

namespace LeanLib

/- The package's `srcDir` joined with the library's `srcDir`. -/
def srcDir (self : LeanLib) : FilePath :=
  self.pkg.srcDir / self.config.srcDir

/-- Whether the given module is considered local to the library. -/
@[inline] def isLocalModule (mod : Name) (self : LeanLib) : Bool :=
  self.config.isLocalModule mod

/-- Whether the given module is a buildable part of the library. -/
@[inline] def isBuildableModule (mod : Name) (self : LeanLib) : Bool :=
  self.config.isBuildableModule mod

/-- The file name of the library's static binary (i.e., `lib{libName}.a`) -/
def staticLibFileName (self : LeanLib) : FilePath :=
  s!"lib{self.config.libName}.a"

/-- The path to the static library in the package's `libDir`. -/
def staticLibFile (self : LeanLib) : FilePath :=
  self.pkg.libDir / self.staticLibFileName

/-- The file name of the library's shared binary (i.e., its `dll`/`dylib`/`so`) . -/
def sharedLibFileName (self : LeanLib) : FilePath :=
  s!"{self.config.libName}.{sharedLibExt}"

/-- The path to the shared library in the package's `libDir`. -/
def sharedLibFile (self : LeanLib) : FilePath :=
  self.pkg.libDir / self.sharedLibFileName

/--
The arguments to pass to `leanc` when compiling the library's C files.
It is `-O3`, `-DNDEBUG`, the package's `moreLeancArgs`, and then the library's
`moreLeancArgs`.

TODO: Use this option.
-/
def leancArgs (self : LeanLib) : Array String :=
  self.pkg.moreLeancArgs ++ self.config.moreLeancArgs

/--
The arguments to pass to `leanc` when linking the shared library.
That is, the package's `moreLinkArgs` plus the library's  `moreLinkArgs`.
-/
def linkArgs (self : LeanLib) : Array String :=
  self.pkg.moreLinkArgs ++ self.config.moreLinkArgs