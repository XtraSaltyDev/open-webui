import asyncio
import importlib
import sys

import pytest


@pytest.fixture()
def socket_main(monkeypatch, tmp_path):
    data_dir = tmp_path / 'data'
    data_dir.mkdir(parents=True, exist_ok=True)

    monkeypatch.setenv('WEBUI_SECRET_KEY', 'test-secret')
    monkeypatch.setenv('DATA_DIR', str(data_dir))

    if 'open_webui.socket.main' in sys.modules:
        module = sys.modules['open_webui.socket.main']
    else:
        module = importlib.import_module('open_webui.socket.main')

    module.SESSION_POOL.clear()
    module.USAGE_POOL.clear()

    yield module

    module.SESSION_POOL.clear()
    module.USAGE_POOL.clear()


@pytest.mark.asyncio
async def test_usage_event_emits_when_active_model_pool_changes(socket_main, monkeypatch):
    emissions = []

    async def fake_emit(event, data, *args, **kwargs):
        emissions.append((event, data))

    monkeypatch.setattr(socket_main.sio, 'emit', fake_emit)

    socket_main.SESSION_POOL['sid-1'] = {'id': 'user-1'}

    await socket_main.usage('sid-1', {'model': 'model-a'})

    assert socket_main.USAGE_POOL == {'model-a': {'sid-1': {'updated_at': socket_main.USAGE_POOL['model-a']['sid-1']['updated_at']}}}
    assert emissions == [('usage', {'model_ids': ['model-a']})]


@pytest.mark.asyncio
async def test_usage_cleanup_emits_when_model_expires(socket_main, monkeypatch):
    emissions = []

    async def fake_emit(event, data, *args, **kwargs):
        emissions.append((event, data))

    async def stop_after_cleanup(delay):
        raise asyncio.CancelledError()

    monkeypatch.setattr(socket_main.sio, 'emit', fake_emit)
    monkeypatch.setattr(socket_main.asyncio, 'sleep', stop_after_cleanup)
    monkeypatch.setattr(socket_main, 'aquire_func', lambda: True)
    monkeypatch.setattr(socket_main, 'renew_func', lambda: True)
    monkeypatch.setattr(socket_main, 'release_func', lambda: True)

    socket_main.USAGE_POOL['model-a'] = {'sid-1': {'updated_at': 0}}

    with pytest.raises(asyncio.CancelledError):
        await socket_main.periodic_usage_pool_cleanup()

    assert socket_main.USAGE_POOL == {}
    assert emissions == [('usage', {'model_ids': []})]
