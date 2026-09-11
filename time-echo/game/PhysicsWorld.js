export class PhysicsWorld {
  constructor({ width = 1600, height = 900, groundY = 760 } = {}) {
    this.width = width;
    this.height = height;
    this.groundY = groundY;
  }

  resolve(position, velocity) {
    const nextPosition = {
      x: Math.max(20, Math.min(this.width - 20, position.x)),
      y: position.y
    };
    const nextVelocity = { x: velocity.x, y: velocity.y };
    let grounded = false;

    if (nextPosition.y >= this.groundY) {
      nextPosition.y = this.groundY;
      nextVelocity.y = 0;
      grounded = true;
    }

    return { position: nextPosition, velocity: nextVelocity, grounded };
  }
}
