enum MemoryLifecycleState {
  proposed,
  confirmed,
  rejected,
  active,
  superseded,
  obsolete,
  archived,
  deleted,
  expired,
}

enum MemoryLifecycleAction {
  propose,
  confirm,
  reject,
  activate,
  replace,
  markObsolete,
  delete,
  expire,
  restore,
}

enum MemoryLifecycleActor { user, assistant, system, historical }
