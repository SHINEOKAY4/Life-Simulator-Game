--!strict
local Types = {}

type PreviewFacingInternal = string
type PreviewKindInternal = "CellObject" | "Floor" | "Wall" | "Roof" | "WallMounted" | "SurfaceMounted" | "Ceiling"

export type PreviewFacing = PreviewFacingInternal
export type PreviewKind = PreviewKindInternal

export type WallMountPose = {
	WorldPosition: Vector3,
	WallNormal: Vector3,
	WallCellX: number,
	WallCellZ: number,
	AttachedFacing: PreviewFacing,
	HeightOffset: number,
	ReferenceCellX: number,
	ReferenceCellZ: number,
}

export type SurfaceMountPose = {
	ParentKey: string,
	LocalPosition: Vector3,
	LocalRotationY: number,
	WorldPosition: Vector3,
	ParentCellX: number?,
	ParentCellZ: number?,
	ParentFacing: PreviewFacing?,
	CanPlace: boolean,
}

export type CeilingMountPose = {
	CellX: number,
	CellZ: number,
	Level: number,
	Facing: PreviewFacing,
	DropStuds: number,
	RotationY: number,
	WorldPosition: Vector3,
	CeilingNormal: Vector3,
	CanPlace: boolean,
}

export type WindowCutoutPose = {
	WorldPosition: Vector3,
	WallNormal: Vector3,
	WallUp: Vector3,
	WallCellX: number,
	WallCellZ: number,
	AttachedFacing: PreviewFacing,
	WallCenter: Vector3,
	HeightOffset: number,
	CutoutWidth: number,
	CutoutHeight: number,
	WallHeight: number,
	WallWidth: number,
	WallThickness: number,
	LocalCenterY: number,
	FrameThickness: number,
	OffsetFromWall: number,
	EffectiveWallWidth: number,
}

export type PreviewPose = {
	ItemId: string,
	CellX: number?,
	CellZ: number?,
	Facing: PreviewFacing,
	Kind: PreviewKind,
	WallMount: WallMountPose?,
	WindowCutout: WindowCutoutPose?,
	SurfaceMount: SurfaceMountPose?,
	CeilingMount: CeilingMountPose?,
	Level: number?,
	LevelHeight: number?,
}

export type PoseCacheComparable = {
	cellX: number,
	cellZ: number,
	facing: PreviewFacing,
	wallPosition: Vector3?,
	windowHeightOffset: number?,
	surfaceParentKey: string?,
	surfaceLocalPosition: Vector3?,
	ceilingDrop: number?,
	ceilingRotation: number?,
}

export type PoseCacheSnapshot = {
	cellX: number?,
	cellZ: number?,
	facing: PreviewFacing?,
	wallPosition: Vector3?,
	surfaceParentKey: string?,
	surfaceLocalPosition: Vector3?,
	windowHeightOffset: number?,
	ceilingDrop: number?,
	ceilingRotation: number?,
}

return Types
