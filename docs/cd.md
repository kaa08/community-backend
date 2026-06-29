# CD

이 문서는 현재 프로젝트에서 CD를 위해 준비한 내용을 정리한다.

## 현재 배포 구성 요약

현재 프로젝트는 GitHub Actions, Amazon ECR, EC2, Docker를 사용해서 백엔드 애플리케이션을 자동 배포한다.

구성 요소는 다음과 같다.

| 구분 | 현재 구성 |
| --- | --- |
| Source repository | GitHub `kaa08/community-backend` |
| CI/CD runner | GitHub Actions |
| Container registry | Amazon ECR `community-ecr` |
| Application server | EC2 |
| Public IP | Elastic IP `3.38.56.109` |
| Application container | `dori-community-be` |
| Database container | `dori-mysql` |
| Container network | `dori-net` |
| External application port | `8080` |
| Health check endpoint | `/actuator/health` |
| Deploy trigger | `main`, `master` branch push |

현재 백엔드 배포 흐름은 다음과 같다.

```text
GitHub main/master push
-> GitHub Actions 실행
-> compileJava
-> test
-> bootJar
-> Docker image build
-> OIDC 기반 AWS Role assume
-> Amazon ECR login
-> ECR에 image push
-> SSH로 EC2 접속
-> EC2에서 ECR image pull
-> 기존 Spring Boot container 제거
-> 새 Spring Boot container 실행
-> /actuator/health 확인
-> health check 성공 시 배포 성공 처리
```

현재 `dev` branch push와 pull request에서는 배포하지 않고 검증만 수행한다.

```text
pull_request, dev push
-> compileJava
-> test
-> bootJar
-> Docker image build
```

## CD 정의

CD는 Continuous Delivery 또는 Continuous Deployment의 줄임말로 사용된다.

이 프로젝트에서 현재 구성한 CD 흐름은 다음과 같다.

```text
GitHub Actions
-> Docker image build
-> Amazon ECR login
-> ECR repository에 image push
-> SSH로 EC2 접속
-> EC2에서 ECR image pull
-> Spring Boot container 재실행
```

현재 단계에서는 ECR push와 EC2 app container 재배포를 GitHub Actions로 자동화했다.

```text
ECR과 AWS 인증 기반 준비
GitHub Actions ECR push
EC2 Docker 수동 배포
GitHub Actions EC2 SSH 배포
```

## Amazon ECR

CD에서 Docker image를 저장할 registry로 Amazon ECR을 사용하기로 했다.

생성한 ECR repository 정보는 다음과 같다.

```text
AWS account ID: 783728775565
Region: ap-northeast-2
Repository name: community-ecr
Repository URI: 783728775565.dkr.ecr.ap-northeast-2.amazonaws.com/community-ecr
```

ECR은 AWS에서 제공하는 private container registry이다. Docker image를 ECR에 push해두면, 이후 EC2/ECS/EKS 같은 AWS 실행 환경에서 해당 image를 pull해서 실행할 수 있다.

ECR push 성공 후 `community-ecr` repository에서 image가 생성된 것을 확인했다.

```text
Repository: community-ecr
Image tag: bfc06070ed0b4364ae7b3f879a594ef3f8264c13
```

## Container Registry 비교

Docker image를 저장하는 registry는 여러 선택지가 있다. 현재 프로젝트에서는 AWS 배포 환경과의 연결성을 고려해서 ECR을 사용했다.

| 구분 | Amazon ECR | Docker Hub | GitHub Container Registry |
| --- | --- | --- | --- |
| 주소 예시 | `783728775565.dkr.ecr.ap-northeast-2.amazonaws.com/community-ecr` | `docker.io/{user}/{image}` | `ghcr.io/{owner}/{image}` |
| 성격 | AWS private registry | 범용 container registry | GitHub repository와 가까운 registry |
| 인증 | AWS IAM, OIDC, ECR login | Docker Hub 계정/token | GitHub token, GitHub Actions 권한 |
| AWS 연동 | 좋음 | 별도 인증 필요 | 별도 인증 필요 |
| GitHub Actions 연동 | OIDC 설정이 필요하지만 장기 access key 없이 가능 | Docker Hub token을 secret에 저장 | GitHub Actions와 쉽게 연동 |
| 공개 image 배포 | 가능하지만 주로 private 용도 | 가장 익숙하고 공개 image 생태계가 큼 | GitHub repository 중심으로 관리하기 좋음 |
| private image 관리 | AWS IAM으로 세밀하게 제어 가능 | plan/정책 확인 필요 | GitHub package 권한과 연결 |
| 이 프로젝트에서의 적합성 | AWS에 배포할 예정이므로 적합 | 공개 image 공유에는 단순함 | GitHub 중심 프로젝트에는 적합하지만 AWS 실행 환경과는 한 단계 더 연결 필요 |

정리하면 다음과 같다.

```text
AWS 배포 중심
-> ECR

가장 범용적인 Docker image 공유
-> Docker Hub

GitHub repository와 package를 함께 관리
-> GHCR
```

## AWS CLI 관리자 사용자

초기에는 root 계정 access key로 AWS CLI를 사용하고 있었지만, root access key를 계속 사용하는 방식은 위험하다.

따라서 root 대신 사용할 IAM 관리자 사용자를 생성했다.

```text
IAM user: admin-kahansol
Policy: AdministratorAccess
```

로컬 AWS CLI도 `admin-kahansol` access key로 다시 설정했다.

정상 설정 여부는 다음 명령으로 확인했다.

```bash
aws sts get-caller-identity
```

정상적으로 설정되면 ARN이 root가 아니라 IAM user로 표시된다.

```text
arn:aws:iam::783728775565:user/admin-kahansol
```

root access key는 장기 보관하지 않고 삭제해야 한다. GitHub Actions에도 root access key를 넣지 않는다.

## GitHub Actions OIDC

GitHub Actions가 AWS에 접근할 때 장기 access key를 GitHub Secrets에 저장하지 않고, OIDC 기반으로 IAM Role을 assume하도록 구성한다.

AWS 계정에 GitHub OIDC Provider가 있는지 확인했다.

```bash
aws iam list-open-id-connect-providers
```

확인된 OIDC Provider는 다음과 같다.

```text
arn:aws:iam::783728775565:oidc-provider/token.actions.githubusercontent.com
```

GitHub Actions가 assume할 IAM Role은 다음 이름으로 준비했다.

```text
Role name: github-actions-ecr-push-role
Role ARN: arn:aws:iam::783728775565:role/github-actions-ecr-push-role
```

이 Role은 GitHub Actions에서 ECR에 image를 push할 때 사용할 역할이다. Trust policy에서는 GitHub repository와 브랜치 조건을 제한한다.

```text
Repository: kaa08/community-backend
Allowed branches: dev, main, master
```

이 구조에서는 GitHub Actions에 AWS access key를 직접 저장하지 않는다. GitHub Actions가 OIDC token을 발급받고, AWS IAM Role이 그 token을 신뢰해서 임시 권한을 발급한다.

```text
GitHub Actions
-> OIDC token 발급
-> AWS IAM Role assume
-> 임시 AWS 권한 획득
-> ECR push 수행
```

## ECR push 권한

ECR push Role에는 `community-ecr` repository에 image를 push할 수 있는 권한을 부여한다.

```text
ecr:GetAuthorizationToken
ecr:BatchCheckLayerAvailability
ecr:InitiateLayerUpload
ecr:UploadLayerPart
ecr:CompleteLayerUpload
ecr:PutImage
ecr:DescribeRepositories
```

## GitHub Secrets

GitHub Actions에서 사용할 repository secrets는 다음과 같다.

```text
AWS_ROLE_ARN=arn:aws:iam::783728775565:role/github-actions-ecr-push-role
AWS_REGION=ap-northeast-2
ECR_REPOSITORY=community-ecr
EC2_HOST=3.38.56.109
EC2_USER=ubuntu
EC2_SSH_KEY={EC2 private key}
```

AWS 관련 값은 GitHub Actions workflow에서 AWS Role assume과 ECR push에 사용된다.

EC2 관련 값은 GitHub Actions가 SSH로 EC2에 접속해 app container를 재배포할 때 사용된다.

## GitHub Actions ECR push

CI/CD workflow에 ECR push 단계를 추가했다.

```text
.github/workflows/ci-cd.yml
```

PR에서는 기존처럼 검증만 수행한다.

```text
compileJava
-> test
-> bootJar
-> docker build
```

`main`, `master` 브랜치에 push될 때는 Docker image를 ECR에 push하고, EC2에 SSH로 접속해 app container를 재배포한다.

`dev` 브랜치 push에서는 compile, test, bootJar, docker build 검증까지만 수행한다.

```text
main/master push
-> compileJava
-> test
-> bootJar
-> docker build
-> AWS Role assume
-> Amazon ECR login
-> ECR push
-> SSH to EC2
-> docker pull
-> docker rm -f dori-community-be
-> docker run
```

OIDC를 사용하려면 GitHub Actions workflow에 다음 권한이 필요하다.

```yaml
permissions:
  contents: read
  id-token: write
```

현재 image tag는 commit SHA를 사용한다.

```text
783728775565.dkr.ecr.ap-northeast-2.amazonaws.com/community-ecr:${{ github.sha }}
```

## GitHub Actions EC2 deploy

ECR push 이후 GitHub Actions에서 EC2에 SSH로 접속해 Spring Boot app container를 재실행하도록 구성했다.

```text
.github/workflows/ci-cd.yml
```

EC2 SSH deploy는 `main`, `master` push event에서만 실행된다.

```text
pull_request
-> compileJava
-> test
-> bootJar
-> docker build

push to dev
-> compileJava
-> test
-> bootJar
-> docker build

push to main/master
-> compileJava
-> test
-> bootJar
-> docker build
-> ECR push
-> EC2 deploy
```

EC2 deploy에서 실행하는 작업은 다음과 같다.

```text
ECR login
-> 새 image pull
-> 기존 dori-community-be container 삭제
-> 새 image로 dori-community-be container 실행
-> /actuator/health 확인
-> unused image 정리
```

EC2 deploy는 app container만 교체한다.

```text
dori-mysql
-> 유지

dori-community-be
-> 새 image로 재실행
```

배포 후에는 Actuator health endpoint로 애플리케이션이 정상 기동했는지 확인한다.

```text
GET /actuator/health
-> 200 OK
-> {"status":"UP"}
```

GitHub Actions deploy script는 최대 90초 동안 health check를 재시도한다.

```text
3초 간격
최대 30회
```

health check가 실패하면 `docker logs dori-community-be`를 출력하고 workflow를 실패 처리한다.

health check 성공 시 GitHub Actions 로그에는 다음과 같은 형태로 기록된다.

```text
{"status":"UP"}Health check succeeded
```

애플리케이션 기동 초기에 다음과 같은 응답이 잠시 발생할 수 있다.

```text
curl: (52) Empty reply from server
curl: (56) Recv failure: Connection reset by peer
```

이는 Spring Boot 애플리케이션이 아직 완전히 요청을 처리할 준비가 되기 전의 일시적인 상태다. 재시도 중 최종적으로 `/actuator/health`가 `{"status":"UP"}`를 반환하면 배포 성공으로 판단한다.

EC2 deploy step은 다음 GitHub Secrets를 사용한다.

```text
EC2_HOST
EC2_USER
EC2_SSH_KEY
AWS_REGION
ECR_REPOSITORY
```

`EC2_SSH_KEY`에는 EC2 key pair private key 전체 내용을 저장한다.

```text
-----BEGIN OPENSSH PRIVATE KEY-----
...
-----END OPENSSH PRIVATE KEY-----
```

시작 줄과 끝 줄을 포함하고, 줄바꿈을 유지해야 한다.

macOS 터미널에서 private key를 복사할 때 마지막에 표시되는 `%` 문자는 shell prompt 표시이므로 GitHub Secret에 포함하지 않는다.

## Actuator health check

배포 성공 여부를 판단하기 위해 Spring Boot Actuator의 health endpoint를 사용한다.

Actuator 의존성은 Spring Boot 애플리케이션에 추가되어 있다.

```text
spring-boot-starter-actuator
```

외부에서 health endpoint를 호출할 수 있도록 Spring Security 설정에서 다음 경로를 인증 없이 접근 가능하게 열어둔다.

```text
/actuator/health
```

노출하는 Actuator endpoint는 `health`로 제한한다.

```yaml
management:
  endpoints:
    web:
      exposure:
        include: health
  endpoint:
    health:
      show-details: never
```

health check endpoint는 다음 응답을 기준으로 정상 여부를 판단한다.

```text
GET /actuator/health
-> {"status":"UP"}
```

GitHub Actions deploy script에서는 새 container 실행 후 최대 30회까지 health check를 재시도한다.

```text
3초 간격
최대 30회
최대 약 90초 대기
```

health check가 끝까지 성공하지 못하면 배포 job은 실패한다.

## ECR image 배포 방식

ECR에 image를 push한 뒤에는 실행 환경이 해당 image를 pull해서 container로 실행해야 한다.

대표적인 배포 방식은 다음과 같다.

```text
GitHub Actions
-> ECR에 image push
-> 실행 환경에서 image pull
-> container 실행
```

배포 방식별 비교는 다음과 같다.

| 방식 | 배포 흐름 | 장점 | 단점 |
| --- | --- | --- | --- |
| EC2에 직접 Docker 실행 | GitHub Actions가 SSH로 EC2에 접속해 `docker pull`, `docker run` 수행 | 구조가 단순하고 서버 내부 동작을 직접 제어하기 쉽다 | 서버 운영, rollback, 무중단 배포, 확장을 직접 구성해야 한다 |
| EC2 + Docker Compose | EC2에서 `docker compose pull`, `docker compose up -d` 수행 | 여러 container를 한 파일로 관리하기 쉽다 | 단일 서버 중심 구성이며 여러 서버로 확장하면 관리가 복잡해진다 |
| ECS | ECR image를 task definition에 반영하고 ECS service를 배포 | ECR, IAM, ALB, CloudWatch와 잘 연결되고 AWS가 container 실행을 관리한다 | ECS cluster, task definition, service, ALB 개념을 알아야 한다 |
| EKS | Kubernetes Deployment가 ECR image를 사용하도록 manifest/Helm 배포 | Kubernetes 표준 방식으로 복잡한 workload와 traffic control에 강하다 | 운영 복잡도와 초기 설정 부담이 크다 |
| Elastic Beanstalk Docker | Elastic Beanstalk 환경에 Docker 애플리케이션 배포 | EC2, load balancer, 배포 흐름을 AWS가 묶어서 관리한다 | 세부 제어가 ECS/EKS보다 제한적이다 |

### EC2에 직접 Docker 실행

EC2 instance에 Docker를 설치하고, GitHub Actions가 SSH로 접속해서 ECR image를 pull한 뒤 container를 재실행하는 방식이다.

```text
GitHub Actions
-> SSH로 EC2 접속
-> aws ecr get-login-password
-> docker pull
-> docker stop / docker rm
-> docker run
```

장점:

```text
구조가 단순하다.
EC2, Docker, network, log 흐름을 직접 이해하기 좋다.
작은 개인 프로젝트에서 시작하기 쉽다.
```

단점:

```text
서버 운영 책임이 크다.
무중단 배포, auto scaling, rollback을 직접 구성해야 한다.
여러 instance로 확장하면 관리가 복잡해진다.
```

### EC2와 Docker Compose

EC2에 `docker-compose.yml`을 두고, app container와 필요한 주변 container를 함께 실행하는 방식이다.

```text
GitHub Actions
-> SSH로 EC2 접속
-> docker compose pull
-> docker compose up -d
```

장점:

```text
단일 EC2에서 여러 container를 함께 관리하기 쉽다.
app, nginx, redis 같은 구성을 한 파일로 묶을 수 있다.
```

단점:

```text
운영 서버에서 compose 파일과 환경변수 관리가 필요하다.
여러 서버로 확장하면 별도 전략이 필요하다.
AWS managed 배포 기능을 직접 누리기는 어렵다.
```

### ECS

ECS는 AWS의 container orchestration 서비스다. ECR image를 task definition에 지정하고, ECS service가 container 실행과 재시작을 관리한다.

```text
GitHub Actions
-> ECR push
-> ECS task definition 갱신
-> ECS service deploy
```

장점:

```text
AWS 환경에서 ECR, IAM, ALB, CloudWatch와 잘 연결된다.
container 재시작, 배포, scaling을 AWS가 관리한다.
Kubernetes보다 진입 장벽이 낮다.
실무 AWS container 배포에서 자주 쓰이는 선택지다.
```

단점:

```text
ECS task definition, service, cluster, ALB 개념을 익혀야 한다.
초기 설정 항목이 EC2 직접 배포보다 많다.
AWS에 강하게 묶인다.
```

### EKS

EKS는 AWS에서 Kubernetes cluster를 관리형으로 제공하는 방식이다. ECR image를 Kubernetes Deployment에서 사용한다.

```text
GitHub Actions
-> ECR push
-> Kubernetes manifest 또는 Helm chart 갱신
-> kubectl apply / helm upgrade
```

장점:

```text
Kubernetes 표준 방식으로 배포할 수 있다.
대규모 서비스, 복잡한 traffic control, 여러 workload 관리에 강하다.
cloud provider 이동성이 ECS보다 높다.
```

단점:

```text
초기 구성 비용과 운영 복잡도가 높다.
cluster, node, ingress, service account, secret 관리가 필요하다.
개인 프로젝트나 작은 서비스에는 과할 수 있다.
```

### Elastic Beanstalk Docker 배포

Elastic Beanstalk은 AWS가 EC2, load balancer, 배포 관리를 묶어서 제공하는 PaaS 성격의 서비스다. Docker 기반 애플리케이션도 배포할 수 있다.

장점:

```text
EC2 직접 운영보다 배포 구성이 단순하다.
AWS가 기본적인 instance, load balancer, 배포 흐름을 관리한다.
작은 서비스에서 빠르게 배포하기 좋다.
```

단점:

```text
세부 제어가 ECS/EKS보다 제한적이다.
서비스가 커지면 내부 동작을 이해하고 조정해야 하는 지점이 생긴다.
```

## EC2 Docker 수동 배포 기록

ECR에 push된 Docker image를 EC2에서 직접 pull한 뒤 Docker container로 실행했다.

현재 배포 확인에 사용한 구성은 다음과 같다.

```text
Region: ap-northeast-2
Elastic IP: 3.38.56.109
Application port: 8080
EC2 IAM Role: ec2-ecr-read-role
ECR repository: community-ecr
Image tag: bfc06070ed0b4364ae7b3f879a594ef3f8264c13
```

EC2에는 다음 두 container를 실행했다.

```text
dori-mysql
-> mysql:8.4
-> Spring Boot app에서 사용할 MySQL database

dori-community-be
-> ECR에서 pull한 Spring Boot image
-> host 8080 port를 container 8080 port에 연결
```

전체 구조는 다음과 같다.

```text
GitHub Actions
-> Docker image build
-> ECR push

EC2
-> ECR image pull
-> dori-mysql container 실행
-> dori-community-be container 실행
-> 3.38.56.109:8080 외부 접근
```

### EC2 IAM Role

EC2가 ECR image를 pull할 수 있도록 EC2 instance에 IAM Role을 연결했다.

```text
Role name: ec2-ecr-read-role
Policy: AmazonEC2ContainerRegistryReadOnly
```

이 Role의 의미는 다음과 같다.

```text
EC2 instance에 AWS access key를 직접 저장하지 않는다.
EC2 instance profile을 통해 ECR read 권한을 얻는다.
EC2에서 ECR image를 pull할 수 있다.
```

### Elastic IP

EC2 public IP가 재시작 시 변경되지 않도록 Elastic IP를 연결했다.

```text
Elastic IP: 3.38.56.109
```

Elastic IP는 생성만 하고 instance에 연결하지 않으면 비용이 발생할 수 있으므로, 생성 후 EC2 instance에 바로 연결했다.

### Security Group

외부에서 Spring Boot app에 접근할 수 있도록 EC2 Security Group inbound rule에 8080 port를 추가했다.

```text
SSH 22
-> source: local IP

Custom TCP 8080
-> source: 0.0.0.0/0
```

현재는 Spring Boot container를 8080 port로 직접 노출한다.

### Docker 설치 확인

EC2에 Docker를 설치하고 실행 상태를 확인했다.

```bash
docker --version
docker ps
```

### ECR login

EC2에서 ECR image를 pull하기 위해 ECR login을 수행한다.

```bash
aws ecr get-login-password --region ap-northeast-2 \
| docker login --username AWS --password-stdin 783728775565.dkr.ecr.ap-northeast-2.amazonaws.com
```

### Docker network

Spring Boot container와 MySQL container가 container 이름으로 통신할 수 있도록 Docker network를 생성했다.

```bash
docker network create dori-net
```

같은 Docker network에 있는 container는 container name을 host처럼 사용할 수 있다.

```text
dori-community-be
-> jdbc:mysql://dori-mysql:3306/pracdb
```

### MySQL container

RDS를 사용하지 않는 상태라 EC2 내부에서 MySQL container를 함께 실행했다.

```bash
docker run -d \
  --name dori-mysql \
  --network dori-net \
  -e MYSQL_ROOT_PASSWORD={DB_PASSWORD} \
  -e MYSQL_DATABASE=pracdb \
  -v dori-mysql-data:/var/lib/mysql \
  mysql:8.4
```

`MYSQL_ROOT_PASSWORD` 값은 Spring Boot container의 `DB_PASSWORD`와 맞춰야 한다.

```text
MYSQL_ROOT_PASSWORD
-> MySQL root password

DB_USERNAME=root
DB_PASSWORD={MYSQL_ROOT_PASSWORD와 같은 값}
```

### Spring Boot 환경변수

Spring Boot container 실행에 필요한 값은 EC2의 `.env` 파일로 주입했다.

```text
~/dori/.env
```

필요한 주요 값은 다음과 같다.

```env
DB_URL=jdbc:mysql://dori-mysql:3306/pracdb?useSSL=false&allowPublicKeyRetrieval=true&serverTimezone=Asia/Seoul
DB_USERNAME=root
DB_PASSWORD={DB_PASSWORD}

JWT_SECRET={JWT_SECRET}
JWT_TOKEN_EXPIRATION_TIME=3600
JWT_REFRESH_EXPIRATION_TIME=1209600

AWS_ACCESS_KEY={AWS_ACCESS_KEY}
AWS_SECRET_KEY={AWS_SECRET_KEY}
AWS_S3_BUCKET={AWS_S3_BUCKET}
AWS_REGION=ap-northeast-2
```

`JWT_SECRET`이 없으면 Spring Boot가 `JwtUtil` bean을 생성하지 못하고 실행에 실패한다.

```text
Could not resolve placeholder 'JWT_SECRET'
```

### Spring Boot container

ECR image를 사용해서 Spring Boot container를 실행했다.

```bash
docker run -d \
  --name dori-community-be \
  --network dori-net \
  --env-file ~/dori/.env \
  -p 8080:8080 \
  783728775565.dkr.ecr.ap-northeast-2.amazonaws.com/community-ecr:bfc06070ed0b4364ae7b3f879a594ef3f8264c13
```

### Container 상태 확인

실행 중인 container는 다음 명령으로 확인했다.

```bash
docker ps
```

확인된 container는 다음과 같다.

```text
dori-community-be
-> 0.0.0.0:8080->8080/tcp

dori-mysql
-> 3306/tcp
```

### Memory 부족과 swap

처음 사용한 EC2 instance는 약 1GiB 메모리 환경이었다. Spring Boot와 MySQL container를 함께 실행하자 사용 가능한 메모리가 매우 적었다.

```text
Mem total: 954Mi
Mem available: 10Mi
Swap: 0B
```

임시로 2GiB swap을 추가해서 container 실행을 안정화했다.

```bash
sudo fallocate -l 2G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
free -h
```

swap 추가 후 상태는 다음과 같았다.

```text
Swap: 2.0Gi
```

### 배포 확인

EC2 내부에서 `localhost:8080` 응답을 확인했다.

```bash
curl -I http://localhost:8080
```

응답은 `401 Unauthorized`였다.

```text
HTTP/1.1 401
```

이 응답은 서버가 죽은 것이 아니라, Spring Security가 인증이 필요한 요청에 대해 응답한 것이다.

외부 브라우저에서는 Swagger UI 접속을 확인했다.

```text
http://3.38.56.109:8080/swagger-ui/index.html
```

최종 확인된 흐름은 다음과 같다.

```text
ECR image
-> EC2에서 pull
-> MySQL container 실행
-> Spring Boot container 실행
-> 외부에서 Swagger UI 접속
```
