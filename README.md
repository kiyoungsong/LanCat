# LanCat 🐈‍⬛

맥북 메뉴바에 사는 이더넷(유선랜) 상태 고양이.
시스템 설정에 들어가지 않아도, 와이파이 아이콘처럼 메뉴바에서 유선랜 상태를 바로 확인할 수 있어요.

| 상태 | 메뉴바 고양이 | 의미 |
|---|---|---|
| 연결됨 | 초록 눈 + 체크, 가끔 눈 깜빡 | 랜선 연결 + 인터넷 OK |
| 인터넷 없음 | 주황 눈 + 와이파이 X | 랜선은 꽂혔는데 인터넷이 안 됨 |
| 랜선 빠짐 | 공유기 위에서 쿨쿨, z가 하나씩 | 이더넷 링크 없음 |

## 기능

- 이더넷 연결 상태를 실시간 감지 (와이파이가 켜져 있어도 유선 기준으로 판단)
- 이더넷 경로로만 인터넷 연결 확인 (15초 간격)
- 왼쪽 클릭: 상세 팝오버 (인터페이스, 링크 속도, IP, 게이트웨이, DNS)
- 오른쪽 클릭: 로그인 시 자동 실행 / 아이콘 테두리 / 이미지 바꾸기 / 상태 미리보기(테스트) / 종료
- **이미지 바꾸기**: 상태별 메뉴바 아이콘과 팝오버 그림을 내 이미지로 교체 (PNG·JPG·GIF·APNG·WebP)
  - 움직이는 GIF를 넣으면 메뉴바 아이콘도 그대로 움직여요
  - 여백 자동 자르기, 흰 배경 자동 지우기, 메뉴바 크기 자동 맞춤
  - 저장 위치: `~/Library/Application Support/LanCat/Custom/`
- 상태가 바뀌면 macOS 알림
- Dock 아이콘 없이 메뉴바에만 상주, 메모리 20~30MB 수준

## 설치

### Releases에서 받기

1. [Releases](../../releases)에서 최신 `LanCat.dmg`를 받아요
2. `LanCat.app`을 `응용 프로그램(Applications)` 폴더로 끌어다 놓아요
3. 처음 실행 시 "확인되지 않은 개발자" 경고가 뜨면 터미널에서 아래를 한 번 실행해요

   ```bash
   xattr -cr /Applications/LanCat.app
   ```

   또는 **시스템 설정 → 개인정보 보호 및 보안**에서 "그래도 열기"를 눌러요.
   (개인 프로젝트라 Apple 개발자 서명을 하지 않았어요.)

### 직접 빌드

Xcode 또는 Command Line Tools(`xcode-select --install`), macOS 13 이상이 필요해요.

```bash
git clone <이 저장소 주소>
cd lancat
./build.sh --run
```

결과물은 `build/LanCat.app`이에요.

## 구조

```
Sources/LanCat/
  main.swift            앱 진입점 (메뉴바 전용 앱)
  AppDelegate.swift     메뉴바 아이콘·프레임 애니메이션·팝오버·알림·메뉴
  NetworkMonitor.swift  NWPathMonitor로 이더넷 감지 + 이더넷 경로로 인터넷 확인
  PopoverView.swift     SwiftUI 팝오버 + 상태별 애니메이션
  ThemeStore.swift      기본/사용자 이미지 관리 (상태별 6칸)
  ImageProcessor.swift  사용자 이미지 다듬기 (프레임 읽기·흰 배경 제거·여백 자르기·크기 맞춤)
  SettingsView.swift    이미지 바꾸기 설정 창
Resources/
  icon_{on,q,off}_N(_dark)(@2x).png  메뉴바 프레임 (18pt, _dark는 테두리 버전)
  scene_{on,q,off}.png               팝오버 일러스트
  AppIcon.png
design/                              원본 일러스트
```

## 테스트 팁

- 오른쪽 클릭 → **상태 미리보기**로 세 가지 상태 화면을 바로 볼 수 있어요
- 실제 "인터넷 없음" 재현:

  ```bash
  sudo route add -host 1.1.1.1 127.0.0.1     # 막기
  sudo route delete -host 1.1.1.1            # 되돌리기
  ```
