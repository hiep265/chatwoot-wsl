import { emitter } from 'shared/helpers/mitt';
import { OPEN_COMMAND_BAR } from 'dashboard/helper/commandbar/events';
import { openCommandBar } from 'dashboard/helper/commandbar/openCommandBar';

describe('openCommandBar', () => {
  afterEach(() => {
    document.body.innerHTML = '';
    vi.restoreAllMocks();
  });

  it('opens the mounted command bar immediately when available', () => {
    const ninja = document.createElement('ninja-keys');
    ninja.open = vi.fn();
    document.body.appendChild(ninja);

    expect(openCommandBar({ parent: 'appearance_settings' })).toBe(true);
    expect(ninja.open).toHaveBeenCalledWith({
      parent: 'appearance_settings',
    });
  });

  it('requests the command bar to mount when it is not available yet', () => {
    const emitSpy = vi.spyOn(emitter, 'emit');

    expect(openCommandBar({ parent: 'snooze_notification' })).toBe(false);
    expect(emitSpy).toHaveBeenCalledWith(OPEN_COMMAND_BAR, {
      parent: 'snooze_notification',
    });
  });
});
