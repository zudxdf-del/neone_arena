export class InputController {
  constructor(target = window) {
    this.state = { left: false, right: false, jump: false, dash: false };
    this.jumpPressed = false;
    this.dashPressed = false;
    this.keys = new Set();
    target.addEventListener('keydown', event => this.handleKey(event, true));
    target.addEventListener('keyup', event => this.handleKey(event, false));
  }

  handleKey(event, down) {
    const key = event.key.toLowerCase();
    if (['arrowleft', 'arrowright', 'arrowup', ' ', 'a', 'd', 'w', 'shift', 'x'].includes(key)) event.preventDefault();
    if (down && !this.keys.has(key)) {
      if (key === ' ' || key === 'arrowup' || key === 'w') this.jumpPressed = true;
      if (key === 'shift' || key === 'x') this.dashPressed = true;
    }
    if (down) this.keys.add(key); else this.keys.delete(key);
    this.state.left = this.keys.has('arrowleft') || this.keys.has('a');
    this.state.right = this.keys.has('arrowright') || this.keys.has('d');
  }

  bindTouchButton(element, action) {
    if (!element) return;
    const press = event => {
      event.preventDefault();
      if (action === 'left') this.state.left = true;
      if (action === 'right') this.state.right = true;
      if (action === 'jump') this.jumpPressed = true;
      if (action === 'dash') this.dashPressed = true;
    };
    const release = event => {
      event.preventDefault();
      if (action === 'left') this.state.left = false;
      if (action === 'right') this.state.right = false;
    };
    element.addEventListener('pointerdown', press, { passive: false });
    element.addEventListener('pointerup', release, { passive: false });
    element.addEventListener('pointercancel', release, { passive: false });
    element.addEventListener('pointerleave', release, { passive: false });
  }

  consume() {
    const result = {
      left: this.state.left,
      right: this.state.right,
      jump: this.jumpPressed,
      dash: this.dashPressed
    };
    this.jumpPressed = false;
    this.dashPressed = false;
    return result;
  }
}
