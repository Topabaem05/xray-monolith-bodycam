# Bodycam for Roblox

Roblox용 바디캠 FPS 패키지입니다. 모든 코드와 문서는 [`roblox/`](roblox/) 폴더에 있습니다.

- **사용법과 설치:** [roblox/README.md](roblox/README.md)
- **포팅한 오픈소스의 라이선스 고지:** [roblox/THIRD-PARTY-NOTICES.md](roblox/THIRD-PARTY-NOTICES.md)
- **Bodycam 동작 명세서:** [roblox/docs/BODYCAM_DESIGN.md](roblox/docs/BODYCAM_DESIGN.md)

## 들어 있는 것

| 패키지 | 내용 |
| --- | --- |
| `Bodycam` | 시야가 에임을 늦게 따라가는 바디캠 카메라, 머리·무기 움직임 |
| `FPSys` | 카메라 효과, 기울이기, 재질별 발소리 |
| `FPSController` | 이동 상태, 무기, 반동 |
| `Presentation` | 생리적 흔들림, 프리 에임, 화면 효과, 뷰모델, 헤드캠 |
| `Realism` | 1인칭 몸 보이기, 시선 복제 |
| `Sound` | 총성 음향, 바디캠 마이크, 이명 (가이드 코드) |
| `Lights` | 총구 섬광, 플래시라이트, 쏴서 끄는 조명, 야간 투시 (가이드 코드) |
| `Ballistics` | 탄도, 관통·도탄, 서버 검증 (가이드 코드) |

## 빠르게 시작하기

[Rojo](https://rojo.space)를 설치한 뒤 실행합니다.

```bash
rojo serve roblox/default.project.json
```

Roblox Studio의 Rojo 플러그인에서 Connect를 누릅니다.

테스트는 Roblox 밖에서 돕니다(Rust 필요).

```bash
cargo build --release --manifest-path roblox/tools/luau-runner/Cargo.toml
```

```bash
cd roblox && tools/luau-runner/target/release/luau-runner tests/run.luau
```

## 이 저장소의 유래

이 저장소는 S.T.A.L.K.E.R. Anomaly용 엔진 포크인
[xray-monolith-bodycam](https://github.com/asuparabekon/xray-monolith-bodycam)에서 갈라져 나왔습니다.
Roblox에서 쓸 수 없는 것은 모두 지웠습니다. 지운 것은 C++ 엔진 소스(`src/`), SDK, 게임 데이터(`gamedata/`),
압축 도구, 엔진 문서, 엔진 빌드 설정입니다. 엔진이 필요하면 위 원본 저장소를 쓰세요.

- 지운 파일은 이 저장소의 git 이력에 남아 있습니다. 그 파일들은 원본의 비상업 라이선스(`License.txt`)를 따릅니다.
- `Bodycam` 패키지는 그 엔진 코드를 옮긴 것이 아니라, 동작 명세서만 보고 새로 구현한 것입니다.
  경위는 [roblox/README.md](roblox/README.md)의 "왜 다시 만들었나"에 있습니다.

## 라이선스

- 포팅한 오픈소스(MIT, Zlib, Unlicense, MPL-2.0)의 고지는 [roblox/THIRD-PARTY-NOTICES.md](roblox/THIRD-PARTY-NOTICES.md)에 있습니다.
- `roblox/src/Realism`과 FPSys의 파생 파일은 MPL-2.0입니다([roblox/src/Realism/LICENSE](roblox/src/Realism/LICENSE)).
- 이 프로젝트에서 새로 쓴 코드에는 아직 라이선스 파일이 없습니다. 공개 배포하려면 저장소 소유자가 라이선스를 정해야 합니다.
- **Roblox Studio에서 실행해 검증하지 않았습니다.** 상업 출시 전에는 법률 검토도 받으세요.
