# Docker Compose Local Environment

이 문서는 Spring Boot 애플리케이션과 MySQL을 Docker Compose로 함께 실행하는 과정을 정리한다.

## 0. 지금까지 구성한 내용

이번 작업에서는 CI와 Docker 기반 실행 환경을 단계적으로 구성했다.

### CI

CI는 Continuous Integration의 줄임말이다. 이 프로젝트에서는 GitHub Actions를 사용해서 PR 또는 주요 브랜치 push 시 코드를 자동 검증하도록 구성했다.

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

즉 현재 CI의 의미는 다음과 같다.

```text
이 코드가 깨끗한 GitHub 실행 환경에서도 컴파일되고 테스트를 통과하는지 확인한다.
Spring Boot jar와 Docker image를 정상적으로 만들 수 있는지 확인한다.
```

현재 CI는 배포를 수행하지 않는다.

```text
CI 성공 = 코드 검증 성공
CI 성공 = Docker image build 성공
CI 성공 != 서버 배포 완료
```

CI workflow 파일은 다음 위치에 있다.

```text
.github/workflows/ci.yml
```

현재 CI는 `main`, `master`, `dev` 브랜치 push와 pull request에서 실행되도록 설정했다.

### 애플리케이션 설정 외부화

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

### .env와 .env.example

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

### Dockerfile

Dockerfile은 Spring Boot 애플리케이션 이미지를 만드는 방법을 정의한다.

현재 Dockerfile은 이미 빌드된 jar를 Docker image 안에 복사해서 실행하는 최소 구성이다.

```dockerfile
FROM eclipse-temurin:21-jre

WORKDIR /app

COPY build/libs/*.jar app.jar

EXPOSE 8080

ENTRYPOINT ["java", "-jar", "app.jar"]
```

현재 Docker image 생성 흐름은 다음과 같다.

```text
./gradlew bootJar
-> build/libs/*.jar 생성
-> docker build
-> Spring Boot 실행 image 생성
```

`docker build` 명령으로 `dori-community-be:local` image 생성을 확인했다.

```bash
docker build -t dori-community-be:local .
```

### .dockerignore

`.dockerignore`는 Docker build context에 불필요한 파일이 포함되지 않도록 제외하는 파일이다.

예를 들어 다음과 같은 파일은 image build에 필요하지 않거나 포함되면 안 된다.

```text
.git
.gradle
.idea
.env
build/reports
build/test-results
spy.log
```

현재 Dockerfile은 `build/libs/*.jar`를 복사하므로 `build` 전체를 ignore하면 안 된다. `build` 전체를 ignore하면 jar 파일도 Docker build context에서 제외되어 image build가 실패한다.

### 단일 docker run에서 DB 연결이 실패한 이유

처음에는 Spring Boot image만 단독으로 실행했다.

```bash
docker run --env-file .env -p 8080:8080 dori-community-be:local
```

이때 `.env`의 DB URL이 `localhost`를 사용하면 DB 연결이 실패한다.

```text
DB_URL=jdbc:mysql://localhost:3306/pracdb
```

Docker container 내부에서 `localhost`는 Mac이 아니라 container 자기 자신이다.

```text
Mac localhost = 로컬 머신
Container localhost = 컨테이너 내부
```

따라서 앱 container가 `localhost:3306`으로 접속하면 container 내부의 MySQL을 찾게 되고, MySQL이 없으므로 `Connection refused`가 발생한다.

### Docker Compose

Docker Compose는 여러 container를 하나의 실행 단위로 관리하는 도구다.

이 프로젝트에서는 Compose로 다음 두 container를 함께 실행한다.

```text
mysql container
app container
```

Compose 실행 흐름은 다음과 같다.

```text
docker compose up --build
-> MySQL container 실행
-> MySQL healthcheck 통과 대기
-> Spring Boot app container 실행
-> app이 mysql:3306으로 DB 연결
```

Compose 안에서 앱은 다음 URL로 DB에 연결한다.

```text
jdbc:mysql://mysql:3306/pracdb
```

여기서 `mysql`은 Docker Compose service 이름이다. Compose 내부 DNS가 service 이름을 container 주소로 resolve해준다.

## 1. 왜 Docker Compose를 사용하는가

단일 Docker container로 Spring Boot 앱만 실행하면 DB 연결을 직접 해결해야 한다.

```text
Spring Boot container
-> DB_URL=jdbc:mysql://localhost:3306/pracdb
-> container 내부 localhost를 바라봄
-> container 안에는 MySQL이 없음
-> Connection refused
```

Docker Compose를 사용하면 Spring Boot 앱과 MySQL을 같은 Docker network에 올릴 수 있다.

```text
Spring Boot app container
-> DB_URL=jdbc:mysql://mysql:3306/pracdb
-> 같은 Compose network의 mysql service로 연결
```

여기서 `mysql`은 Docker Compose의 service 이름이다. Compose 내부 DNS가 service 이름을 container 주소로 resolve해준다.

## 2. 현재 구성

현재 로컬 Compose 구성은 두 개의 service로 나뉜다.

```text
mysql
-> MySQL 8.4
-> database: pracdb
-> volume: mysql-data
-> container port: 3306
-> host port: 3307

app
-> Spring Boot jar 기반 Docker image
-> mysql service가 healthy 상태가 된 뒤 시작
-> port: 8080
```

## 3. 환경변수

실제 비밀값은 Git에 올리지 않는 `.env`에 둔다.

```text
.env
-> 실제 로컬 실행 값
-> Git ignore 대상

.env.example
-> 필요한 환경변수 목록
-> 비밀값 없이 커밋 가능
```

Compose에서 중요한 값은 다음과 같다.

```env
MYSQL_DATABASE=pracdb
MYSQL_ROOT_PASSWORD=local-password
```

Spring Boot app container는 Compose에서 아래 DB URL을 사용한다.

```env
DB_URL=jdbc:mysql://mysql:3306/pracdb?useSSL=false&allowPublicKeyRetrieval=true&serverTimezone=Asia/Seoul
```

앱 컨테이너와 MySQL 컨테이너는 같은 Compose network 안에 있으므로 `mysql:3306`으로 연결한다. Mac에서 직접 Compose MySQL에 접속할 때는 host port로 열어둔 `localhost:3307`을 사용한다.

## 4. 실행 순서

현재 Dockerfile은 이미 만들어진 jar를 image에 복사하는 최소 구성이다. 따라서 Compose 실행 전에 jar를 먼저 만든다.

```bash
./gradlew bootJar
```

그다음 Compose로 MySQL과 앱을 함께 실행한다.

```bash
docker compose up --build
```

백그라운드로 실행하려면 다음 명령을 사용한다.

```bash
docker compose up --build -d
```

## 5. 확인 명령

실행 중인 container 확인:

```bash
docker compose ps
```

앱 로그 확인:

```bash
docker compose logs -f app
```

MySQL 로그 확인:

```bash
docker compose logs -f mysql
```

전체 중지:

```bash
docker compose down
```

DB volume까지 삭제:

```bash
docker compose down -v
```

`down -v`는 MySQL 데이터까지 삭제하므로, 로컬 데이터를 유지해야 할 때는 사용하지 않는다.
