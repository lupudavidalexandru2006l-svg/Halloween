// CLIENT: one input owner for keyboard, touch and gamepad. Every action works on all three.
export function createInput() {
  const keys = new Set();
  const state = {
    move: { x: 0, z: 0 },       // x = east (right on screen), z = south (up the screen, toward the zones)
    interact: false,             // hold to freeze / interact
    touch: false,
    botMove: null, botInteract: false, // the playtest bot drives the same signals
  };
  const handlers = { panel: [] };
  addEventListener('keydown', (e) => {
    if (e.repeat) return;
    keys.add(e.code);
    if (e.code === 'KeyT') handlers.panel.forEach((f) => f());
  });
  addEventListener('keyup', (e) => keys.delete(e.code));
  addEventListener('blur', () => keys.clear());

  // touch thumbstick: appears where the left thumb lands
  const stick = document.getElementById('stick'), knob = stick.querySelector('.knob');
  let stickId = null, origin = null, stickVec = { x: 0, z: 0 };
  addEventListener('pointerdown', (e) => {
    if (e.pointerType !== 'touch') return;
    state.touch = true; document.documentElement.style.setProperty('--touch-lift', '110px');
    if (stickId !== null || e.clientX > innerWidth * 0.45 || e.target.closest('.block, .prompt, .offer, #panel')) return;
    stickId = e.pointerId; origin = { x: e.clientX, y: e.clientY };
    stick.style.display = 'block'; stick.style.left = origin.x - 60 + 'px'; stick.style.top = origin.y - 60 + 'px';
  });
  addEventListener('pointermove', (e) => {
    if (e.pointerId !== stickId) return;
    let dx = e.clientX - origin.x, dy = e.clientY - origin.y; const m = Math.hypot(dx, dy), max = 50;
    if (m > max) { dx = (dx / m) * max; dy = (dy / m) * max; }
    knob.style.transform = `translate(${dx}px, ${dy}px)`;
    stickVec = { x: dx / max, z: -dy / max };
  });
  const endStick = (e) => { if (e.pointerId !== stickId) return; stickId = null; stickVec = { x: 0, z: 0 }; stick.style.display = 'none'; knob.style.transform = ''; };
  addEventListener('pointerup', endStick); addEventListener('pointercancel', endStick);

  // the prompt itself is the hold button on touch and mouse
  let promptHeld = false;
  function bindHoldButton(el) {
    el.addEventListener('pointerdown', (e) => { e.preventDefault(); promptHeld = true; el.setPointerCapture?.(e.pointerId); });
    const up = () => { promptHeld = false; };
    el.addEventListener('pointerup', up); el.addEventListener('pointercancel', up); el.addEventListener('lostpointercapture', up);
  }

  function update() {
    let x = 0, z = 0;
    if (keys.has('KeyW') || keys.has('ArrowUp')) z += 1;
    if (keys.has('KeyS') || keys.has('ArrowDown')) z -= 1;
    if (keys.has('KeyD') || keys.has('ArrowRight')) x += 1;
    if (keys.has('KeyA') || keys.has('ArrowLeft')) x -= 1;
    x += stickVec.x; z += stickVec.z;
    let pad = false;
    const gp = navigator.getGamepads?.()[0];
    if (gp) {
      const gx = gp.axes[0] || 0, gz = -(gp.axes[1] || 0);
      if (Math.hypot(gx, gz) > 0.2) { x += gx; z += gz; }
      pad = !!(gp.buttons[0]?.pressed || gp.buttons[2]?.pressed);
    }
    x = -x; // the camera looks south (+z), so screen-right is world -x
    if (state.botMove) { x = state.botMove.x; z = state.botMove.z; } // the bot steers in world space
    const m = Math.hypot(x, z); if (m > 1) { x /= m; z /= m; }
    state.move = { x, z };
    state.interact = state.botMove ? state.botInteract : (keys.has('KeyE') || keys.has('Space') || promptHeld || pad);
  }
  return { state, update, bindHoldButton, onPanel: (f) => handlers.panel.push(f) };
}
