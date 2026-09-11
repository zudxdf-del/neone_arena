export class PlayerController {
  constructor({ role, networkManager, physics }) {
    this.role = role;
    this.networkManager = networkManager;
    this.physics = physics;
    this.position = { x: 0, y: 0 };
    this.velocity = { x: 0, y: 0 };
    this.grounded = false;
    this.jumpCount = 0;
    this.input = { left: false, right: false, jump: false, dash: false };
    this.speed = 240;
    this.acceleration = 1800;
    this.friction = 2200;
    this.jumpVelocity = 620;
    this.gravity = 1800;
    this.maxFallSpeed = 1100;
    this.maxJumps = role === 'future' ? 2 : 1;
    this.dashSpeed = 760;
    this.dashDuration = 0.13;
    this.dashRemaining = 0;
    this.dashCooldown = 0.65;
    this.dashCooldownRemaining = 0;
    this.lastSentInput = 0;
  }

  setInput(nextInput) {
    this.input = {
      left: Boolean(nextInput.left),
      right: Boolean(nextInput.right),
      jump: Boolean(nextInput.jump),
      dash: Boolean(nextInput.dash)
    };
  }

  setPosition(x, y) {
    this.position.x = x;
    this.position.y = y;
  }

  update(dt) {
    const step = Math.min(Math.max(dt, 0), 0.05);
    this.dashCooldownRemaining = Math.max(0, this.dashCooldownRemaining - step);

    if (this.input.dash && this.dashCooldownRemaining === 0 && this.dashRemaining === 0) {
      const direction = this.input.left ? -1 : this.input.right ? 1 : (this.velocity.x < 0 ? -1 : 1);
      this.velocity.x = direction * this.dashSpeed;
      this.velocity.y = 0;
      this.dashRemaining = this.dashDuration;
      this.dashCooldownRemaining = this.dashCooldown;
    }

    if (this.dashRemaining > 0) {
      this.dashRemaining = Math.max(0, this.dashRemaining - step);
      this.position.x += this.velocity.x * step;
      return this.snapshot();
    }

    const axis = (this.input.right ? 1 : 0) - (this.input.left ? 1 : 0);
    const target = axis * this.speed;
    const rate = axis === 0 ? this.friction : this.acceleration;
    const difference = target - this.velocity.x;
    const amount = Math.sign(difference) * Math.min(Math.abs(difference), rate * step);
    this.velocity.x += amount;

    if (this.input.jump && this.jumpCount < this.maxJumps) {
      this.velocity.y = -this.jumpVelocity;
      this.jumpCount += 1;
      this.grounded = false;
      this.input.jump = false;
    }

    this.velocity.y = Math.min(this.maxFallSpeed, this.velocity.y + this.gravity * step);
    this.position.x += this.velocity.x * step;
    this.position.y += this.velocity.y * step;

    if (this.physics && typeof this.physics.resolve === 'function') {
      const resolved = this.physics.resolve(this.position, this.velocity, this.role);
      this.position.x = resolved.position.x;
      this.position.y = resolved.position.y;
      this.velocity.x = resolved.velocity.x;
      this.velocity.y = resolved.velocity.y;
      this.grounded = Boolean(resolved.grounded);
      if (this.grounded) this.jumpCount = 0;
    }

    return this.snapshot();
  }

  snapshot() {
    return {
      x: this.position.x,
      y: this.position.y,
      vx: this.velocity.x,
      vy: this.velocity.y,
      grounded: this.grounded,
      role: this.role
    };
  }
}
