# SyncSwitch

SyncSwitch는 여러 사용자가 실시간으로 도메인별 온/오프 토글을 동기화할 수 있는 웹 애플리케이션입니다.

## 주요 기능

### 1. 스위치 생성
- 사용자가 자신만의 스위치를 생성 가능 (예: `/test`, `/myswitch`)
- 직관적인 URL 기반 접근

### 2. 실시간 동기화
- 각 도메인마다 독립적인 온/오프 토글 스위치
- 해당 도메인에 접속한 모든 사용자에게 실시간으로 동기화
- WebSocket을 통한 실시간 통신

### 3. 권한 관리
- **생성자 권한**: 스위치 수정/삭제, 비밀번호 설정
- 비밀번호로 보호된 도메인 설정 가능

### 4. 테마 지원
다음의 다양한 테마를 지원합니다:
- iOS 6, iOS 7
- Apple Liquid Glass
- Google Material 1, 2, 3
- Microsoft Fluent 1, 2

## 기술 스택

- **Backend**: Node.js + Express
- **Real-time**: WebSocket
- **Frontend**: HTML5, CSS3, JavaScript
- **Database**: JSON/SQLite (선택 가능)

## 설치 방법

```bash
git clone https://github.com/doetoeri/syncswitch.git
cd syncswitch
npm install
npm start
```

## 프로젝트 구조

```
syncswitch/
├── server/
│   ├── app.js
│   ├── routes/
│   └── models/
├── public/
│   ├── index.html
│   ├── css/
│   │   ├── themes/
│   │   └── style.css
│   └── js/
│       ├── app.js
│       └── themes/
├── package.json
└── README.md
```

## 라이선스

MIT License
