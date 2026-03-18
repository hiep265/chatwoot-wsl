import { emitter } from 'shared/helpers/mitt';
import { OPEN_COMMAND_BAR } from './events';

const getMountedCommandBar = () => document.querySelector('ninja-keys');

export const openCommandBar = options => {
  const ninja = getMountedCommandBar();

  if (ninja) {
    ninja.open(options);
    return true;
  }

  emitter.emit(OPEN_COMMAND_BAR, options);
  return false;
};
