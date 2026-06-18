# CD

이 문서는 현재 프로젝트에서 CD를 위해 준비한 내용을 정리한다.

## CD 정의

CD는 Continuous Delivery 또는 Continuous Deployment의 줄임말로 사용된다.

이 프로젝트에서 현재 구성한 CD 흐름은 다음과 같다.

```text
GitHub Actions
-> Docker image build
-> Amazon ECR login
-> ECR repository에 image push
```

현재 단계에서는 ECR push까지 자동화했고, 서버 배포까지는 자동화하지 않았다.

```text
현재 완료된 것 = ECR과 AWS 인증 기반 준비, GitHub Actions ECR push
아직 하지 않은 것 = EC2/ECS/EKS 등 실행 환경에 자동 배포
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
```

이 값들은 GitHub Actions workflow에서 AWS Role assume과 ECR push에 사용된다.

## GitHub Actions ECR push

CI workflow에 ECR push 단계를 추가했다.

```text
.github/workflows/ci.yml
```

PR에서는 기존처럼 검증만 수행한다.

```text
compileJava
-> test
-> bootJar
-> docker build
```

`main`, `master`, `dev` 브랜치에 push될 때는 Docker image를 ECR에 push한다.

```text
compileJava
-> test
-> bootJar
-> docker build
-> AWS Role assume
-> Amazon ECR login
-> ECR push
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
