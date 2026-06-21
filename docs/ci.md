# CI

이 문서는 현재 프로젝트에 구성한 CI 내용을 정리한다.

## CI 정의

CI는 Continuous Integration의 줄임말이다. 이 프로젝트에서는 GitHub Actions를 사용해서 PR 또는 주요 브랜치 push 시 코드를 자동 검증하도록 구성했다.

현재 CI의 의미는 다음과 같다.

```text
새로운 코드가 깨끗한 GitHub 실행 환경에서도 컴파일되는지 확인한다.
테스트가 통과하는지 확인한다.
Spring Boot jar를 정상적으로 만들 수 있는지 확인한다.
Docker image를 정상적으로 만들 수 있는지 확인한다.
```

현재 CI는 배포를 수행하지 않는다.

```text
CI 성공 = 코드 검증 성공
CI 성공 = Docker image build 성공
CI 성공 != 서버 배포 완료
```

## Workflow 파일

CI workflow 파일은 다음 위치에 있다.

```text
.github/workflows/ci.yml
```

현재 CI는 `main`, `master`, `dev` 브랜치 push와 pull request에서 실행되도록 설정했다.

```yaml
on:
  push:
    branches:
      - main
      - master
      - dev
  pull_request:
```

## 현재 CI 실행 단계

현재 CI가 하는 일은 다음과 같다.

```text
GitHub Actions runner 실행
-> repository checkout
-> Java 21 설치
-> Gradle 환경 준비
-> ./gradlew compileJava
-> ./gradlew test
-> ./gradlew bootJar
-> docker build
```

각 단계의 의미는 다음과 같다.

```text
compileJava
-> Java source compile 확인

test
-> 테스트 코드 실행

bootJar
-> Spring Boot 실행 jar 생성 확인

docker build
-> Dockerfile 기반 image build 확인
```

## GitHub Rulesets

GitHub Rulesets를 사용해서 `main`, `master`, `dev` 브랜치에 보호 규칙을 적용했다.

적용 대상 브랜치는 다음과 같다.

```text
main
master
dev
```

설정한 규칙은 다음과 같다.

```text
Require a pull request before merging
Require status checks to pass
Require branches to be up to date before merging
Block force pushes
```

필수 status check는 GitHub Actions의 `Build and Test`이다.

```text
Required status check: Build and Test
```

이 설정의 의미는 다음과 같다.

```text
main/master/dev 브랜치에는 PR 기반으로 변경을 반영한다.
Build and Test 체크가 통과해야 merge할 수 있다.
base 브랜치 최신 변경사항을 반영한 상태에서 CI가 통과해야 한다.
force push를 차단한다.
```

즉 현재 CI는 단순히 성공/실패를 보여주는 것에서 끝나지 않고, protected branch에 merge하기 위한 필수 검증 조건으로 사용된다.

## 애플리케이션 설정 외부화

기존에는 `application.yml`을 Git에 올리지 않는 방식이었다. 하지만 CI/CD 환경에서는 설정 파일 자체가 없으면 애플리케이션이 어떤 설정 키를 필요로 하는지 알기 어렵다.

그래서 `application.yml`은 커밋 가능한 파일로 두고, 민감한 값만 환경변수로 분리했다.

```yaml
spring:
  datasource:
    url: ${DB_URL}
    username: ${DB_USERNAME}
    password: ${DB_PASSWORD}

jwt:
  secret: ${JWT_SECRET}

aws:
  credentials:
    access-key: ${AWS_ACCESS_KEY}
    secret-key: ${AWS_SECRET_KEY}
```

이 구조의 목적은 다음과 같다.

```text
설정 파일의 구조는 Git에 남긴다.
비밀번호, JWT secret, AWS key 같은 민감값은 Git에 남기지 않는다.
로컬, CI, 배포 환경에서 환경변수로 값을 주입한다.
```

## .env와 .env.example

로컬 실행에 필요한 실제 값은 `.env`에 둔다.

```text
.env
-> 실제 로컬 실행 값
-> Git ignore 대상
```

프로젝트에 필요한 환경변수 목록은 `.env.example`에 둔다.

```text
.env.example
-> 필요한 환경변수 목록
-> 비밀값 없이 커밋 가능
```

정리하면 다음과 같다.

```text
.env = 실제 값, 커밋 금지
.env.example = 샘플 값, 커밋 가능
```

## Docker image build 검증

현재 CI에는 Docker image build 검증이 포함되어 있다.

```bash
docker build -t dori-community-be:${{ github.sha }} .
```

이 단계는 image를 registry에 push하지 않고, Dockerfile로 image가 정상 생성되는지만 확인한다.
