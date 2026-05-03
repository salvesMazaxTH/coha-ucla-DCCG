export const entityView = new Map();

export function registerEntityView(entityId, element) {
  entityView.set(entityId, element);
}

export function getEntityView(entityId) {
  return entityView.get(entityId);
}

export function removeEntityView(entityId) {
  entityView.delete(entityId);
}