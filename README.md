# HAMH Matter Electrical Meter (0x0514)

HAMH의 `Electrical Meter (Power/Energy/Voltage/Current)`가 만드는
Matter Device Type `0x0514`를 SmartThings에서 `powerMeter` / `energyMeter`
Capability로 표시하기 위한 테스트용 커스텀 Edge Driver입니다.

## 포함 기능
- ElectricalPowerMeasurement.ActivePower -> SmartThings powerMeter (W)
- ElectricalEnergyMeasurement.CumulativeEnergyImported -> SmartThings energyMeter (Wh)
- Refresh 버튼 지원
- **스마트싱스 앱 설정 (Preferences)**
  1. **조회(폴링) 주기**: 기본 15초 (0 입력 시 폴링 비활성화)
  2. **최소 변화량 필터 (Threshold)**: 기본 1.0W (미세한 소수점 노이즈로 인한 기록 도배 방지)
  3. **소수점 표시 방식**: 정수 (예: 405 W) vs 소수점 1자리 (예: 405.2 W)
  4. **전력 보정 계수 (Multiplier)**: 기본 1.0 (CT 센서 오차 보정용 배율)

## 설치

SmartThings 공식 CLI와 Edge CLI plugin이 설치되어 있어야 합니다.

압축을 푼 뒤 이 폴더의 상위 경로에서:

    smartthings edge:drivers:package ./hamh-matter-electrical-meter --install

처음 실행할 경우 CLI가 개인 Driver Channel과 대상 Hub를 선택하도록 안내할 수 있습니다.

수동으로 진행할 경우 공식 흐름은 다음과 같습니다.

    smartthings edge:channels:create
    smartthings edge:channels:enroll
    smartthings edge:drivers:package ./hamh-matter-electrical-meter
    smartthings edge:channels:assign
    smartthings edge:drivers:install

## 기존 기기에 적용

드라이버를 Hub에 설치한 뒤 SmartThings 앱에서
`전력미터` 장치의 드라이버 변경 메뉴가 표시되면
`HAMH Matter Electrical Meter`로 변경합니다.

드라이버 변경 메뉴에 이 드라이버가 나타나지 않으면,
해당 bridged Matter endpoint에 대해 SmartThings가 사용자 드라이버 전환을 허용하지 않는 상태일 수 있습니다.
그 경우 Edge CLI 로그를 확인한 뒤 다음 방법을 결정해야 합니다.

## 로그

    smartthings edge:drivers:logcat

목록에서 `HAMH Matter Electrical Meter`를 선택합니다.

전력값이 들어오면 ActivePower 관련 attribute report가 보여야 합니다.
