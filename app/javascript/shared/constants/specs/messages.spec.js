import { MESSAGE_TYPE } from '../messages';

describe('shared message constants', () => {
  it('defines the session trace message type for staff-side consumers', () => {
    expect(MESSAGE_TYPE.SESSION_TRACE).toBe(4);
  });
});
