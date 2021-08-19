/-
Copyright (c) 2017 Microsoft Corporation. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Gabriel Ebner, Sebastian Ullrich, Mac Malone
-/
import Lean.Data.Name
import Lean.Elab.Import
import Lake.Target
import Lake.BuildModule
import Lake.Resolve
import Lake.Package

open System
open Lean hiding SearchPath

namespace Lake

-- # Build Target

abbrev PackageTarget := ActiveLakeTarget (Package × NameMap ModuleTarget)

namespace PackageTarget

def package (self : PackageTarget) :=
  self.artifact.1

def moduleTargetMap (self : PackageTarget) : NameMap ModuleTarget :=
  self.artifact.2

def moduleTargets (self : PackageTarget) : Array (Name × ModuleTarget) :=
  self.moduleTargetMap.fold (fun arr k v => arr.push (k, v)) #[]

end PackageTarget

-- # Build Modules

def Package.buildModuleTargetDAGFor
(mod : Name)  (oleanDirs : List FilePath) (depsTarget : ActiveLakeTarget PUnit)
(self : Package) : IO (ModuleTarget × NameMap ModuleTarget) := do
  let fetch := fetchModuleWithLocalImports self oleanDirs depsTarget
  throwOnCycle <| buildRBTop fetch mod |>.run {}

def Package.buildModuleTargetDAG
(oleanDirs : List FilePath) (depsTarget : ActiveLakeTarget PUnit) (self : Package) :=
  self.buildModuleTargetDAGFor self.moduleRoot oleanDirs depsTarget

def Package.buildModuleTargets
(mods : List Name) (oleanDirs : List FilePath)
(depsTarget : ActiveLakeTarget PUnit) (self : Package)
: IO (List ModuleTarget) := do
  let fetch : ModuleTargetFetch := fetchModuleWithLocalImports self oleanDirs depsTarget
  throwOnCycle <| mods.mapM (buildRBTop fetch) |>.run' {}

-- # Configure/Build Packages

def Package.buildTargetWithDepTargetsFor
(mod : Name) (depTargets : List PackageTarget) (self : Package)
: IO PackageTarget := do
  let depsTarget ← ActiveTarget.all <|
    (← self.buildMoreDepsTarget).withArtifact arbitrary :: depTargets
  let oLeanDirs := depTargets.map (·.package.oleanDir)
  let (target, targetMap) ← self.buildModuleTargetDAGFor mod oLeanDirs depsTarget
  return {target with artifact := ⟨self, targetMap⟩}

def Package.buildTargetWithDepTargets
(depTargets : List PackageTarget) (self : Package) : IO PackageTarget :=
  self.buildTargetWithDepTargetsFor self.moduleRoot depTargets

partial def Package.buildTarget (self : Package) : IO PackageTarget := do
  let deps ← solveDeps self
  -- build dependencies recursively
  -- TODO: share build of common dependencies
  let depTargets ← deps.mapM (·.buildTarget)
  self.buildTargetWithDepTargets depTargets

def Package.buildDepTargets (self : Package) : IO (List PackageTarget) := do
  let deps ← solveDeps self
  deps.mapM (·.buildTarget)

def Package.buildDeps (self : Package) : IO (List Package) := do
  let deps ← solveDeps self
  let targets ← deps.mapM (·.buildTarget)
  try targets.forM (·.materialize) catch e =>
    -- actual error has already been printed within the task
    throw <| IO.userError "Build failed."
  return deps

def configure (pkg : Package) : IO Unit :=
  discard pkg.buildDeps

def Package.build (self : Package) : IO PUnit := do
  let target ← self.buildTarget
  try target.materialize catch _ =>
    -- actual error has already been printed within the task
    throw <| IO.userError "Build failed."

def build (pkg : Package) : IO PUnit :=
  pkg.build

-- # Print Paths

def Package.buildModuleTargetsWithDeps
(deps : List Package) (mods : List Name)  (self : Package)
: IO (List ModuleTarget) := do
  let oleanDirs := deps.map (·.oleanDir)
  let depsTarget ← ActiveTarget.all <|
    (← self.buildMoreDepsTarget).withArtifact arbitrary :: (← deps.mapM (·.buildTarget))
  self.buildModuleTargets mods oleanDirs depsTarget

def Package.buildModulesWithDeps
(deps : List Package) (mods : List Name)  (self : Package)
: IO PUnit := do
  let targets ← self.buildModuleTargetsWithDeps deps mods
  try targets.forM (·.materialize) catch e =>
    -- actual error has already been printed within target
    throw <| IO.userError "Build failed."

def printPaths (pkg : Package) (imports : List String := []) : IO Unit := do
  let deps ← solveDeps pkg
  unless imports.isEmpty do
    let imports := imports.map (·.toName)
    let localImports := imports.filter (·.getRoot == pkg.moduleRoot)
    pkg.buildModulesWithDeps deps localImports
  IO.println <| SearchPath.toString <| pkg.oleanDir :: deps.map (·.oleanDir)
  IO.println <| SearchPath.toString <| pkg.srcDir :: deps.map (·.srcDir)