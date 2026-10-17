# CD

이 문서는 Dori Community 프로젝트에서 구성한 배포 인프라와 CD 흐름을 정리한다.

## 전체 구성 요약

현재 프로젝트는 백엔드와 프론트엔드를 분리해서 배포한다.

| 구분 | 현재 구성 |
| --- | --- |
| Backend repository | GitHub `kaa08/community-backend` |
| Frontend repository | GitHub `kaa08/community-FE` |
| Backend runtime | Spring Boot, Docker |
| Frontend runtime | Vite React 정적 빌드 |
| Backend image registry | Amazon ECR `community-ecr` |
| Backend server | EC2 |
| Backend domain | `https://api.dori-ka.cloud` |
| Frontend hosting | S3 `dori-community-fe` |
| Frontend CDN | CloudFront |
| Frontend domain | `https://dori-ka.cloud`, `https://www.dori-ka.cloud` |
| DNS | Route 53 Hosted Zone |
| Backend TLS | Let's Encrypt, Certbot, Nginx |
| Frontend TLS | ACM `us-east-1`, CloudFront |
| CI/CD runner | GitHub Actions |

전체 요청 흐름은 다음과 같다.

```text
Client
-> https://dori-ka.cloud
-> Route 53
-> CloudFront
-> S3 dori-community-fe
-> React application

React application
-> https://api.dori-ka.cloud
-> Route 53
-> EC2 Elastic IP
-> Nginx HTTPS reverse proxy
-> Spring Boot Docker container
-> MySQL container
```

## CD 정의

CD는 Continuous Delivery 또는 Continuous Deployment의 줄임말이다.

이 프로젝트에서 CD는 다음 의미로 사용한다.

```text
코드가 main/master 브랜치에 반영되면
GitHub Actions가 빌드, 검증, 업로드, 배포를 자동으로 수행한다.
```

현재 배포는 다음 기준으로 나뉜다.

| 이벤트 | 백엔드 동작 | 프론트엔드 동작 |
| --- | --- | --- |
| Pull Request | compile, test, bootJar, Docker build 검증 | npm ci, lint, build 검증 |
| dev push | 배포 없이 검증만 수행 | 배포 없이 검증만 수행 |
| main/master push | ECR push 후 EC2 배포 | S3 업로드 후 CloudFront 캐시 무효화 |

## Backend 배포 구성

백엔드는 Docker image로 패키징한 뒤 ECR에 저장하고, EC2에서 해당 image를 pull해서 실행한다.

```text
GitHub Actions
-> compileJava
-> test
-> bootJar
-> Docker image build
-> OIDC 기반 AWS Role assume
-> Amazon ECR login
-> ECR image push
-> SSH로 EC2 접속
-> EC2에서 ECR image pull
-> 기존 Spring Boot container 제거
-> 새 Spring Boot container 실행
-> Actuator health check
-> 실패하면 이전 image로 복구 후 배포 실패 처리
```

### Amazon ECR

Docker image 저장소로 Amazon ECR을 사용한다.

```text
AWS account ID: 783728775565
Region: ap-northeast-2
Repository name: community-ecr
Repository URI: 783728775565.dkr.ecr.ap-northeast-2.amazonaws.com/community-ecr
```

image tag는 GitHub commit SHA를 사용한다.

```text
783728775565.dkr.ecr.ap-northeast-2.amazonaws.com/community-ecr:${{ github.sha }}
```

### EC2

백엔드 애플리케이션은 EC2에서 Docker container로 실행한다.

```text
Elastic IP: 3.38.56.109
Application container: dori-community-be
Database container: dori-mysql
Docker network: dori-net
```

현재 RDS는 사용하지 않고, EC2 내부에서 MySQL container를 함께 실행한다.

```text
dori-community-be
-> jdbc:mysql://dori-mysql:3306/pracdb

dori-mysql
-> mysql:8.4
```

Spring Boot container 실행 시 환경변수는 EC2의 `~/dori/.env` 파일로 주입한다.

```text
DB_URL
DB_USERNAME
DB_PASSWORD
JWT_SECRET
JWT_TOKEN_EXPIRATION_TIME
JWT_REFRESH_EXPIRATION_TIME
AWS_ACCESS_KEY
AWS_SECRET_KEY
AWS_S3_BUCKET
AWS_REGION
```

### Nginx reverse proxy

외부 요청은 Spring Boot container에 직접 들어가지 않고 Nginx를 거친다.

```text
Client
-> Nginx 443
-> 127.0.0.1:8080
-> Spring Boot container
```

Spring Boot container는 외부에 직접 8080 port를 열지 않고 localhost에만 바인딩한다.

```bash
docker run -d \
  --name dori-community-be \
  --network dori-net \
  --env-file ~/dori/.env \
  -p 127.0.0.1:8080:8080 \
  "$ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG"
```

이 구조에서는 EC2 Security Group에서 8080 inbound를 열 필요가 없다.

현재 외부 접근에 필요한 inbound rule은 다음과 같다.

| Type | Port | Source |
| --- | --- | --- |
| HTTP | 80 | 0.0.0.0/0 |
| HTTPS | 443 | 0.0.0.0/0 |
| SSH | 22 | 작업자 IP |

### Backend HTTPS

백엔드 API 도메인은 `api.dori-ka.cloud`이다.

```text
api.dori-ka.cloud
-> Route 53 A record
-> EC2 Elastic IP 3.38.56.109
```

HTTPS 인증서는 Let's Encrypt와 Certbot으로 발급했다.

```bash
sudo certbot --nginx -d api.dori-ka.cloud
```

Nginx는 `api.dori-ka.cloud`에 대해 443 HTTPS 요청을 받고 Spring Boot container로 proxy한다.

```text
https://api.dori-ka.cloud
-> Nginx 443
-> http://127.0.0.1:8080
```

정상 동작은 다음 명령으로 확인했다.

```bash
curl https://api.dori-ka.cloud/actuator/health
```

```json
{"status":"UP"}
```

### Actuator health check

배포 성공 여부를 확인하기 위해 Spring Boot Actuator health endpoint를 사용한다.

```text
GET /actuator/health
-> {"status":"UP"}
```

GitHub Actions deploy step에서는 새 container 실행 후 health check를 최대 30회 재시도한다.

```text
3초 간격
최대 30회
각 요청의 연결 제한 2초, 전체 요청 제한 5초
요청 시간을 포함하면 한 차례의 검증에 최대 약 4분 소요
```

health check가 성공하면 배포 성공으로 처리한다. 새 container 실행이나 health check가 실패하면 container log를 출력하고 이전 image로 복구를 시도한다. 복구에 성공해도 새 버전 배포는 실패 처리한다.

### Backend 자동 롤백

GitHub Actions의 `Deploy to EC2` 단계에서 다음 순서로 실행한다.

1. EC2의 `~/dori/deploy.lock`에 `flock` 잠금을 획득한다. 다른 배포가 같은 잠금을 사용 중이면 container를 변경하기 전에 실패 처리한다.
2. 환경변수 파일과 Docker network를 확인한다. 기존 container가 있으면 변경되지 않는 image ID(`sha256:...`)를 저장하고 현재 health check가 성공하는지 확인한다. 기존 서비스가 비정상이면 자동 배포를 중단하고 수동 복구 대상으로 안내한다.
3. ECR 로그인과 새 image 다운로드를 완료한다. 이 단계가 실패하면 기존 container는 유지한다.
4. 기존 container를 제거하고 새 image로 실행한다. health check가 성공하면 배포를 완료한다.
5. 새 container 실행 또는 health check가 실패하면 로그를 출력하고 실패한 container를 제거한다.
6. 저장한 이전 image ID로 container를 다시 실행하고 동일한 health check를 수행한다.
7. 복구 성공 여부를 로그에 남기고 job은 실패로 종료한다. 기존 Discord 알림도 배포 실패를 알리며, 복구 결과는 Actions 로그에서 확인한다.

최초 배포처럼 이전 image가 없으면 자동 롤백을 수행할 수 없다. 이전 image의 재실행이나 health check도 실패하면 수동 복구가 필요하다. Workflow의 강제 취소나 EC2 자체 장애는 이 실패 처리만으로 복구를 보장하지 않는다.

자동 롤백은 기존 network, `.env`, port binding으로 애플리케이션 image를 되돌리는 방식이다. DB나 환경변수 파일은 복원하지 않으므로 DB 변경 시 이전 버전과 호환되는지 확인해야 한다. container 교체 중에는 서비스가 잠시 중단되며 무중단 배포는 아니다.

복구할 image를 남겨두기 위해 배포 직후의 `docker image prune -f`는 제거했다. image가 누적될 수 있으므로 디스크 사용량과 별도의 image 보관 정책을 관리한다. 원격 명령 제한은 새 버전과 복구 버전의 health check 시간을 고려해 15분으로 설정한다.

Workflow에 포함된 배포 Bash 스크립트는 다음 명령으로 테스트한다. Ruby 표준 라이브러리만 사용하며, Docker, AWS, HTTP 요청, 대기는 가짜 명령으로 대체한다. 실제 서버에는 접속하지 않는다. CI에서도 동일한 테스트를 실행한다.

```bash
ruby tests/deploy_rollback_test.rb
```

### Backend 수동 롤백

자동 롤백이 실패하거나 운영자가 특정 버전으로 복구해야 할 때는 아래 절차로 마지막으로 정상 동작했던 image를 다시 실행한다. 진행 전에 GitHub Actions에서 실행 중인 배포가 없는지 확인한다.

> 이 절차는 애플리케이션 container만 교체하며, 교체 중에는 서비스가 잠시 중단된다. MySQL container와 데이터는 삭제하지 않는다. 진행 중에는 새 배포가 동시에 실행되지 않도록 주의한다. DB 스키마나 데이터가 변경된 경우 이전 애플리케이션 버전과 호환되는지 먼저 확인한다. 이미지 롤백은 DB 변경을 되돌리지 않는다.

1. GitHub Actions의 백엔드 `CI/CD` 실행 목록에서 장애가 발생하기 **전**, 실제 서비스가 정상 동작했던 `main` 또는 `master` 배포를 찾는다. 해당 실행의 commit **전체 SHA**를 복사한다. 가장 최근 image가 반드시 정상 image인 것은 아니다.
2. EC2에 SSH로 접속하고 아래 값을 설정한다. `IMAGE_TAG`에는 1번에서 복사한 전체 SHA를 넣는다.

```bash
AWS_REGION=ap-northeast-2
ECR_REGISTRY=783728775565.dkr.ecr.ap-northeast-2.amazonaws.com
ECR_REPOSITORY=community-ecr
IMAGE_TAG=여기에_정상_배포된_전체_커밋_SHA
```

3. ECR에 로그인한 뒤 image를 미리 pull한다. **로그인과 pull이 성공한 것을 확인하기 전에는 기존 container를 제거하지 않는다.** 해당 태그가 ECR에서 삭제되었거나 권한이 없으면 멈추고 원인을 확인한다.

```bash
aws ecr get-login-password --region "$AWS_REGION" | docker login --username AWS --password-stdin "$ECR_REGISTRY"
```

```bash
docker pull "$ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG"
```

4. 현재 애플리케이션 container를 교체한다. 이 명령은 `dori-community-be`만 제거하며 `dori-mysql`은 건드리지 않는다.

```bash
docker rm -f dori-community-be
```

```bash
docker run -d \
  --name dori-community-be \
  --network dori-net \
  --env-file ~/dori/.env \
  -p 127.0.0.1:8080:8080 \
  "$ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG"
```

5. 애플리케이션이 시작된 후 EC2 내부와 외부에서 각각 health check를 확인한다.

```bash
# EC2에서 실행
curl --fail --show-error http://localhost:8080/actuator/health
```

```bash
# 로컬 PC 등 외부에서 실행
curl --fail --show-error https://api.dori-ka.cloud/actuator/health
```

두 요청 모두 `{"status":"UP"}`을 반환하면 확인된 경로의 health check는 정상이다. 이어서 로그인과 게시글 조회 등 주요 기능도 점검한다. 시작 중에는 응답까지 시간이 걸릴 수 있다. 계속 실패하면 다음 명령으로 로그를 확인한다.

```bash
docker logs --tail 100 dori-community-be
```

롤백한 커밋 SHA와 사유를 기록한다. 이 작업은 운영 중인 container만 변경하며 Git의 `master` 코드나 GitHub Actions 배포 이력은 되돌리지 않는다. 이후 `master`에 다시 push하면 그 커밋이 다시 배포될 수 있다.

2026-10-17 수동 검증에서는 `5049fdc029ecdd4d9eaa8f064ca5ee6cc9687829`에서 `702c51f44a983da7ed116f1b629f541ad01b668d`로 교체한 후 EC2 내부와 외부 HTTPS health check의 `UP`을 확인했다. 이후 `5049fdc029ecdd4d9eaa8f064ca5ee6cc9687829`로 복귀하고 두 경로의 `UP`을 다시 확인했다. 이 기록은 수동 롤백 검증이며, 자동 롤백의 실제 EC2 동작 검증은 별도로 필요하다.

## Backend GitHub Actions

백엔드 workflow 파일은 다음 위치에 있다.

```text
.github/workflows/ci-cd.yml
```

`pull_request`, `dev push`에서는 검증만 수행한다.

```text
compileJava
-> test
-> bootJar
-> Docker image build
```

`main`, `master` push에서는 검증 후 배포까지 수행한다.

```text
compileJava
-> test
-> bootJar
-> Docker image build
-> ECR push
-> EC2 deploy
-> health check
```

GitHub Actions가 AWS에 접근할 때 장기 access key를 저장하지 않고 OIDC 기반 IAM Role을 사용한다.

```text
GitHub Actions
-> OIDC token 발급
-> AWS IAM Role assume
-> 임시 AWS 권한 획득
-> ECR push 수행
```

백엔드 배포에 사용하는 GitHub Secrets는 다음과 같다.

```text
AWS_ROLE_ARN=arn:aws:iam::783728775565:role/github-actions-ecr-push-role
AWS_REGION=ap-northeast-2
ECR_REPOSITORY=community-ecr
EC2_HOST=3.38.56.109
EC2_USER=ubuntu
EC2_SSH_KEY={EC2 private key}
```

`EC2_SSH_KEY`에는 private key의 시작 줄과 끝 줄을 포함한다.

```text
-----BEGIN OPENSSH PRIVATE KEY-----
...
-----END OPENSSH PRIVATE KEY-----
```

터미널 복사 시 마지막에 보이는 `%` 문자는 shell prompt 표시이므로 secret에 포함하지 않는다.

## Frontend 배포 구성

프론트엔드는 Vite React 프로젝트를 build한 뒤 S3에 정적 파일로 업로드하고, CloudFront를 통해 사용자에게 제공한다.

```text
Vite React
-> npm run build
-> dist/
-> S3 dori-community-fe
-> CloudFront
-> dori-ka.cloud
```

현재 프론트엔드 구성은 다음과 같다.

| 구분 | 현재 구성 |
| --- | --- |
| Repository | GitHub `kaa08/community-FE` |
| Project directory | `community-react` |
| Build output | `community-react/dist` |
| S3 bucket | `dori-community-fe` |
| CloudFront distribution ID | `E3QWPRQ2JSY34P` |
| CloudFront domain | `di5zfhyzvjs5q.cloudfront.net` |
| Domain | `dori-ka.cloud`, `www.dori-ka.cloud` |
| Certificate | ACM `us-east-1` |

### Frontend API base URL

프론트엔드에서 백엔드 API 주소는 Vite 환경변수로 분리했다.

```javascript
baseURL: import.meta.env.VITE_API_BASE_URL
```

production build에서는 다음 값을 사용한다.

```env
VITE_API_BASE_URL=https://api.dori-ka.cloud
```

`VITE_` 환경변수는 build 결과물에 포함된다. 따라서 비밀값이 아니라 브라우저에 공개되어도 되는 값만 넣는다.

### S3

S3 bucket에는 Vite build 결과물인 `dist/` 내부 파일을 업로드한다.

```bash
npm run build
aws s3 sync dist/ s3://dori-community-fe --delete
```

초기에는 S3 정적 웹사이트 호스팅만 사용했지만, 최종 구성에서는 CloudFront를 앞단에 두었다.

```text
Client
-> CloudFront
-> S3 bucket
```

CloudFront에서 private S3 bucket access를 허용하도록 설정했다. 이 구성에서는 사용자가 S3 bucket에 직접 접근하는 대신 CloudFront를 통해 정적 파일을 조회한다.

### CloudFront

CloudFront는 S3의 정적 파일을 CDN으로 제공하고, 사용자 도메인과 HTTPS를 담당한다.

```text
CloudFront alternate domain names:
- dori-ka.cloud
- www.dori-ka.cloud
```

CloudFront는 global service이므로 distribution 자체는 특정 region에 종속되지 않는다. 다만 CloudFront에 연결할 ACM 인증서는 `us-east-1` region에서 발급해야 한다.

### ACM certificate

프론트엔드 사용자 도메인에 HTTPS를 적용하기 위해 ACM 인증서를 발급했다.

```text
Region: us-east-1
Domains:
- dori-ka.cloud
- www.dori-ka.cloud
Validation method: DNS validation
```

ACM에서 제공한 CNAME record를 Route 53에 추가해서 DNS 검증을 완료했다.

### Route 53

가비아에서 구매한 `dori-ka.cloud` 도메인의 네임서버를 Route 53 Hosted Zone으로 위임했다.

Route 53 Hosted Zone의 NS record는 다음과 같다.

```text
ns-984.awsdns-59.net
ns-1698.awsdns-20.co.uk
ns-1270.awsdns-30.org
ns-507.awsdns-63.com
```

프론트엔드 도메인은 CloudFront distribution으로 alias 연결했다.

```text
dori-ka.cloud
-> A Alias
-> CloudFront distribution

www.dori-ka.cloud
-> A Alias
-> CloudFront distribution
```

백엔드 API 도메인은 EC2 Elastic IP로 연결했다.

```text
api.dori-ka.cloud
-> A record
-> 3.38.56.109
```

### React Router SPA fallback

React Router는 `/login`, `/posts` 같은 경로를 브라우저에서 처리한다. 사용자가 해당 경로를 직접 열거나 새로고침하면 CloudFront와 S3는 실제 object를 찾으려고 한다.

이를 해결하기 위해 CloudFront custom error response를 설정했다.

```text
403 -> /index.html -> HTTP 200
404 -> /index.html -> HTTP 200
```

이 설정으로 `/login` 같은 SPA 경로를 직접 열어도 React application이 정상 렌더링된다.

### Frontend HTTPS 확인

프론트엔드 HTTPS 응답은 다음 명령으로 확인했다.

```bash
curl -I https://dori-ka.cloud
curl -I https://www.dori-ka.cloud
```

확인된 주요 응답은 다음과 같다.

```text
HTTP/2 200
server: AmazonS3
x-cache: Miss from cloudfront
via: ...cloudfront.net (CloudFront)
```

## Frontend GitHub Actions

프론트엔드 workflow 파일은 repository root에 둔다.

```text
.github/workflows/ci-cd.yml
```

프론트엔드 repository 안에서 실제 Vite 프로젝트는 `community-react` 하위에 있으므로 GitHub Actions의 working directory를 `community-react`로 설정한다.

```yaml
defaults:
  run:
    working-directory: community-react
```

`pull_request`, `dev push`에서는 build 검증만 수행한다.

```text
npm ci
-> npm run lint
-> npm run build
```

`main`, `master` push에서는 build 후 S3와 CloudFront에 배포한다.

```text
npm ci
-> npm run lint
-> npm run build
-> upload artifact
-> download artifact
-> AWS Role assume
-> S3 sync
-> CloudFront invalidation
```

프론트엔드 배포에 사용하는 GitHub Secrets는 다음과 같다.

```text
AWS_ROLE_ARN={frontend deploy role arn}
AWS_REGION=ap-northeast-2
S3_BUCKET=dori-community-fe
CLOUDFRONT_DISTRIBUTION_ID=E3QWPRQ2JSY34P
```

프론트엔드 배포용 IAM Role은 S3 업로드와 CloudFront invalidation 권한을 가진다.

```text
s3:ListBucket
s3:GetObject
s3:PutObject
s3:DeleteObject
cloudfront:CreateInvalidation
```

## CORS

프론트엔드 도메인이 CloudFront 사용자 도메인으로 변경되면서 백엔드 CORS 허용 origin도 함께 설정했다.

허용한 production frontend origin은 다음과 같다.

```text
https://dori-ka.cloud
https://www.dori-ka.cloud
```

CORS preflight는 다음 명령으로 확인했다.

```bash
curl -i -X OPTIONS 'https://api.dori-ka.cloud/auth/login' \
  -H 'Origin: https://dori-ka.cloud' \
  -H 'Access-Control-Request-Method: POST' \
  -H 'Access-Control-Request-Headers: content-type,authorization'
```

정상 응답에는 다음 header가 포함된다.

```text
Access-Control-Allow-Origin: https://dori-ka.cloud
Access-Control-Allow-Credentials: true
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
| private image 관리 | AWS IAM으로 세밀하게 제어 가능 | plan/정책 확인 필요 | GitHub package 권한과 연결 |
| 이 프로젝트에서의 적합성 | AWS에 배포할 예정이므로 적합 | 공개 image 공유에는 단순함 | GitHub 중심 프로젝트에는 적합하지만 AWS 실행 환경과는 한 단계 더 연결 필요 |

## ECR image 배포 방식 비교

ECR에 image를 push한 뒤에는 실행 환경이 해당 image를 pull해서 container로 실행해야 한다.

| 방식 | 배포 흐름 | 장점 | 단점 |
| --- | --- | --- | --- |
| EC2에 직접 Docker 실행 | GitHub Actions가 SSH로 EC2에 접속해 `docker pull`, `docker run` 수행 | 구조가 단순하고 서버 내부 동작을 직접 제어하기 쉽다 | 서버 운영, rollback, 무중단 배포, 확장을 직접 구성해야 한다 |
| EC2 + Docker Compose | EC2에서 `docker compose pull`, `docker compose up -d` 수행 | 여러 container를 한 파일로 관리하기 쉽다 | 단일 서버 중심 구성이며 여러 서버로 확장하면 관리가 복잡해진다 |
| ECS | ECR image를 task definition에 반영하고 ECS service를 배포 | ECR, IAM, ALB, CloudWatch와 잘 연결되고 AWS가 container 실행을 관리한다 | ECS cluster, task definition, service, ALB 개념을 알아야 한다 |
| EKS | Kubernetes Deployment가 ECR image를 사용하도록 manifest/Helm 배포 | Kubernetes 표준 방식으로 복잡한 workload와 traffic control에 강하다 | 운영 복잡도와 초기 설정 부담이 크다 |
| Elastic Beanstalk Docker | Elastic Beanstalk 환경에 Docker 애플리케이션 배포 | EC2, load balancer, 배포 흐름을 AWS가 묶어서 관리한다 | 세부 제어가 ECS/EKS보다 제한적이다 |

## 현재 완료 상태

현재 완료된 항목은 다음과 같다.

```text
Backend
-> Dockerfile 작성
-> ECR repository 생성
-> GitHub Actions OIDC Role 구성
-> ECR image push 자동화
-> EC2 Docker 배포
-> Nginx reverse proxy 구성
-> api.dori-ka.cloud DNS 연결
-> Let's Encrypt HTTPS 적용
-> Actuator health check 기반 배포 검증

Frontend
-> Vite production build
-> S3 정적 파일 배포
-> CloudFront CDN 구성
-> dori-ka.cloud, www.dori-ka.cloud DNS 연결
-> ACM 인증서 기반 HTTPS 적용
-> React Router SPA fallback 설정
-> GitHub Actions S3 sync, CloudFront invalidation 구성

Integration
-> Frontend API base URL을 https://api.dori-ka.cloud로 분리
-> Backend CORS에 CloudFront frontend domain 허용
```

현재 구성은 개인 프로젝트 기준으로 백엔드와 프론트엔드의 1차 배포 자동화가 완료된 상태다.
