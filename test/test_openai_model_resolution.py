import importlib

import pytest


@pytest.fixture()
def openai_router(monkeypatch, tmp_path):
    data_dir = tmp_path / 'data'
    data_dir.mkdir(parents=True, exist_ok=True)

    monkeypatch.setenv('WEBUI_SECRET_KEY', 'test-secret')
    monkeypatch.setenv('DATA_DIR', str(data_dir))

    return importlib.import_module('open_webui.routers.openai')


def test_resolve_openai_model_id_keeps_available_request(openai_router):
    models = {
        'requested-model': {'id': 'requested-model'},
        'fallback-model': {'id': 'fallback-model'},
    }

    assert openai_router.resolve_openai_model_id('requested-model', models, 'fallback-model') == 'requested-model'


def test_resolve_openai_model_id_prefers_available_default(openai_router):
    models = {
        'new-model': {'id': 'new-model'},
        'default-model': {'id': 'default-model'},
    }

    assert openai_router.resolve_openai_model_id('old-model', models, 'default-model') == 'default-model'


def test_resolve_openai_model_id_falls_back_to_first_available(openai_router):
    models = {
        'new-model': {'id': 'new-model'},
        'other-model': {'id': 'other-model'},
    }

    assert openai_router.resolve_openai_model_id('old-model', models, '') == 'new-model'
