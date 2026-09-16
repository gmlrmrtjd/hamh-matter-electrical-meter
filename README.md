# HAMH Matter Electrical Meter (0x0514)

Home Assistant Matter Hub(HAMH)를 통해 SmartThings로 공유한 전력미터의
전력값이 정상적으로 표시되지 않는 문제를 해결하기 위한 SmartThings Edge Driver입니다.

HAMH에서 생성하는 Matter Device Type `0x0514` (Electrical Meter)의 데이터를
SmartThings의 `powerMeter` / `energyMeter` Capability로 표시합니다.

## 설치

아래 링크를 통해 SmartThings Edge Driver 채널에 등록합니다.

**[HAMH Custom Drivers 채널 등록](https://bestow-regional.api.smartthings.com/invite/kVM55JnveKM5)**

채널 등록 후:

1. `HAMH Matter Electrical Meter` 드라이버를 설치합니다.
2. SmartThings 앱에서 HAMH를 통해 추가된 전력미터를 선택합니다.
3. **드라이버 → 다른 드라이버 선택**으로 이동합니다.
4. `HAMH Matter Electrical Meter`를 선택합니다.

드라이버가 적용되면 기존에 `연결됨`으로만 표시되던 전력미터에서
전력 및 에너지 값을 확인할 수 있습니다.

## 지원 기능

- **현재 전력**
  - Matter `ElectricalPowerMeasurement.ActivePower`
  - SmartThings `powerMeter`
  - 단위: W

- **누적 에너지**
  - Matter `ElectricalEnergyMeasurement.CumulativeEnergyImported`
  - SmartThings `energyMeter`
  - 단위: Wh

- **Refresh**
  - SmartThings에서 현재 측정값을 새로 조회할 수 있습니다.

## 설정

SmartThings 앱의 드라이버 설정에서 다음 항목을 변경할 수 있습니다.

### 조회(폴링) 주기

기본값은 **15초**입니다.

`0`으로 설정하면 폴링을 비활성화할 수 있습니다.

### 최소 변화량 필터 (Threshold)

기본값은 **1.0 W**입니다.

미세한 소수점 단위의 전력 변화로 인해 SmartThings 이벤트 기록이
지나치게 많이 생성되는 것을 줄이기 위한 설정입니다.

### 소수점 표시 방식

전력값의 표시 방식을 선택할 수 있습니다.

- 정수: `405 W`
- 소수점 1자리: `405.2 W`

### 전력 보정 계수 (Multiplier)

기본값은 **1.0**입니다.

측정값 보정이 필요한 경우 배율을 설정할 수 있습니다.

예를 들어 실제 소비전력과 측정값에 차이가 있는 경우 보정에 사용할 수 있습니다.

## 문제 해결

드라이버 설치 후에도 기존 드라이버가 사용되고 있다면 SmartThings 앱에서
해당 전력미터의 **드라이버 → 다른 드라이버 선택** 메뉴를 확인하세요.

목록에서 `HAMH Matter Electrical Meter`를 선택하면 됩니다.

드라이버 변경 메뉴 또는 드라이버가 나타나지 않는 경우에는
SmartThings의 기기 상태나 Matter endpoint 인식 상태에 따라
사용자 드라이버 변경이 제한된 경우일 수 있습니다.

## 로그 확인

문제 확인이 필요한 경우 SmartThings CLI에서 다음 명령을 사용할 수 있습니다.

```bash
smartthings edge:drivers:logcat
```

목록에서 `HAMH Matter Electrical Meter`를 선택합니다.

정상적으로 전력 데이터가 수신되고 있다면
`ActivePower` 관련 Matter Attribute Report를 확인할 수 있습니다.

## 소스 코드

이 저장소에는 `HAMH Matter Electrical Meter` Edge Driver의 소스 코드가 공개되어 있습니다.

주요 파일:

- `config.yml` - Edge Driver 설정
- `fingerprints.yml` - Matter 기기 매칭 정보
- `profiles/electrical-meter.yml` - SmartThings Device Profile
- `src/init.lua` - 드라이버 동작 코드

## 이용약관

이 드라이버는 개인 프로젝트로 제공됩니다.

사용 전 [TERMS.md](./TERMS.md)를 확인해 주세요.

## 개발자

라이언킹구하기