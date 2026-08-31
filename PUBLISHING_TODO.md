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
- [x] 9. Живой end-to-end на Kali: strict mode, замок держит, `eth0`/IPv6/ICMP/UDP закрыты.

Осталось:

- [ ] Перезагрузка с новым `iron-dome-boot.service` (старая версия не грузилась:
      `Restart=` запрещён для `Type=oneshot`). Проверить `systemctl status iron-dome-boot.service`.
- [ ] `render` + `install` на Kali поверх live-конфигурации: живой `outline.json`
      лежит в `/etc/shadowsocks-libev/`, проект ставит в `/opt/irondome/config/`.
- [ ] Прогнать `sudo tor-bridges` с заведомо мёртвым мостом — проверить откат.
- [ ] `INTEGRATION_PROFILE=none` на системе, где нет `cliproxysvc`.
- [ ] `shellcheck -S warning bin/irondome lib/*.sh` + GitHub Actions на smoke test.

Минимальный безопасный public-репозиторий состоит из:

- шаблонов
- инструкций
- скриптов-генераторов
- без живой боевой конфигурации и без пользовательских секретов
