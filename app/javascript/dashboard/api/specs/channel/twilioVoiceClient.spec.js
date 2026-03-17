const twilioMock = vi.hoisted(() => {
  const device = {
    removeAllListeners: vi.fn(),
    on: vi.fn(),
    updateToken: vi.fn(),
    disconnectAll: vi.fn(),
    destroy: vi.fn(),
    connect: vi.fn(),
  };

  return {
    moduleLoadCount: 0,
    device,
    Device: vi.fn(() => device),
    getToken: vi.fn(),
  };
});

vi.mock('@twilio/voice-sdk', () => {
  twilioMock.moduleLoadCount += 1;

  return {
    Device: twilioMock.Device,
  };
});

vi.mock('../../channel/voice/voiceAPIClient', () => ({
  default: {
    getToken: twilioMock.getToken,
  },
}));

const loadClient = async () => {
  const module = await import('../../channel/voice/twilioVoiceClient');
  return module.default;
};

describe('dashboard/api/channel/voice/twilioVoiceClient', () => {
  beforeEach(() => {
    vi.resetModules();
    vi.clearAllMocks();
    twilioMock.moduleLoadCount = 0;
    twilioMock.getToken.mockResolvedValue({
      token: 'voice-token',
      account_id: 'account-1',
    });
  });

  it('defers loading the voice sdk until the device is initialized', async () => {
    await loadClient();

    expect(twilioMock.moduleLoadCount).toBe(0);
  });

  it('loads the voice sdk when initializing the device', async () => {
    const client = await loadClient();

    await expect(client.initializeDevice(7)).resolves.toBe(twilioMock.device);

    expect(twilioMock.getToken).toHaveBeenCalledWith(7);
    expect(twilioMock.Device).toHaveBeenCalledWith(
      'voice-token',
      expect.objectContaining({
        allowIncomingWhileBusy: true,
        disableAudioContextSounds: true,
        appParams: { account_id: 'account-1' },
      })
    );
  });
});
