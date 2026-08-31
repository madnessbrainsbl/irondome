# Publishing TODO

Перед публикацией на GitHub:

- [x] 1. Проверить, что нигде не осталось реальных IP/VPS/bridge-значений.
- [x] 2. Заменить machine-specific пути на шаблоны (`__PROJECT_ROOT__`, `__HOME__`, `%h`).
- [x] 3. Убедиться, что нигде нет email, refresh/access token и auth-state.
- [x] 4. Один canonical install flow: `setup → render → install → start`.
- [x] 5. README для public-аудитории.
- [x] 6. Smoke test: `scripts/smoke-test.sh` (render → install --root → проверки).
- [x] 7. Лицензия: MIT, файл `LICENSE`.
- [x] 8. Threat model и limitations: `docs/THREAT_MODEL.md`.

Осталось:

- [ ] Прогнать `scripts/smoke-test.sh` на Linux и приложить вывод.
- [ ] `shellcheck -S warning bin/irondome lib/*.sh` + GitHub Actions на оба шага.
- [ ] Живой end-to-end тест: `tor → 1080 → 8119 → strict → stop`.
- [ ] Проверить `INTEGRATION_PROFILE=none` на чистой машине (создание `cliproxysvc`).

Минимальный безопасный public-репозиторий состоит из:

- шаблонов
- инструкций
- скриптов-генераторов
- без живой боевой конфигурации и без пользовательских секретов
