# 🎬 KaArchive - 개인 커뮤니티 프로젝트

---
## 프로젝트 설명
**KaArchive**는 영화를 보고 느낀 감상과 소소한 일상을 기록하고, 다른 사람들과 공유할 수 있는 커뮤니티 서비스입니다.

Spring Boot 기반의 풀스택 프로젝트로, **회원가입/로그인**, **게시글 CRUD**, **댓글 CRUD**, **이미지 업로드** 등의 기능을 제공합니다. 단순한 기능 구현을 넘어 개발 과정에서 발생한 문제를 해결하고, 서비스의 안정성과 성능을 개선하는 데 집중했습니다.

---

## 📚 기술 스택

### Backend
- Java 21
- Spring Boot 3.5.6
- Spring Data JPA
- Spring Security
- MySQL
- AWS S3
- Swagger UI + Rest Docs
- JaCoCo

### Frontend
- HTML / CSS / JS or React
- github: https://github.com/100-hours-a-week/3-dori-ka-community-FE
---

## ✨ 주요 기능

- 회원가입 / 로그인 / 로그아웃
- 게시글 및 댓글 CRUD
- Presigned-URL을 통한 Aws S3 파일 업로드
- Spring Cache + JdbcTemplate Batch Update를 통한 조회수 증가
- Swagger UI + Rest Docs를 사용한 문서화
- JaCoCo를 통한 테스트 커버리지 측정 및 리포트를 자동화

---

## 📁 프로젝트 구조
```markdown
### Backend (Spring Boot)

com.example.community
├── CommunityApplication.java
│
├── common
│   ├── BasicTimeEntity.java
│   │
│   ├── annotation
│   │   └── AuthUser.java
│   │
│   ├── aop
│   │   └── LoggingAspect.java
│   │
│   ├── exception
│   │   ├── ApiExceptionHandler.java
│   │   ├── ErrorMessage.java
│   │   ├── custom
│   │   │   ├── CustomException.java
│   │   │   ├── BadRequestException.java
│   │   │   ├── DuplicatedException.java
│   │   │   ├── ResourceNotFoundException.java
│   │   │   ├── UnauthorizedException.java
│   │   │   └── ForbiddenException.java
│   │   └── GlobalExceptionHandler.java
│   │
│   ├── util
│   │   ├── AuthValidator.java
│   │   └── DateTimeUtils.java
│   │
│   └── BaseTimeEntity.java
│
├── config
│   ├── AuditingConfig.java
│   ├── AwsS3Config.java
│   ├── CacheConfig.java
│   ├── CorsConfig.java
│   ├── PasswordEncoderConfig.java
│   ├── SecurityConfig.java
│   └── SwaggerConfig.java
│
├── controller
│   ├── AuthController.java
│   ├── CommentController.java
│   ├── MyPageController.java
│   ├── PostController.java
│   ├── PostImageController.java
│   ├── PostLikeController.java
│   ├── PresignedUrlController.java
│   └── UserController.java
│
├── domain
│   ├── Comment.java
│   ├── Post.java
│   ├── PostImage.java
│   ├── PostLike.java
│   ├── RefreshToken.java
│   ├── Role.java
│   └── User.java
│
├── dto
│   ├── request
│   │   ├── user
│   │   │   ├── ChangePasswordDto.java
│   │   │   ├── UserLoginDto.java
│   │   │   ├── UserSignUpDto.java
│   │   │   └── UserUpdateDto.java
│   │   ├── post
│   │   │   ├── PostRequestDto.java
│   │   │   └── PostUpdateDto.java
│   │   ├── image
│   │   │   └── PresignedUrlRequestDto.java
│   │   └── comment
│   │       └── CommentRequestDto.java
│   │
│   ├── response
│   │   ├── user
│   │   │   ├── LoginResponse.java
│   │   │   ├── SignUpResponse.java
│   │   │   └── UserDetailResponse.java
│   │   ├── post
│   │   │   ├── PostCreateResponse.java
│   │   │   ├── PostDetailResponse.java
│   │   │   ├── PostLikeResponse.java
│   │   │   ├── PostListResponse.java
│   │   │   └── PostImageResponse.java
│   │   ├── s3
│   │   │   └── PresignedUrlResponse.java
│   │   └── comment
│   │       └── CommentResponse.java
│
├── repository
│   ├── comment
│   │   └── CommentRepository.java
│   ├── post
│   │   ├── PostImageRepository.java
│   │   ├── PostJdbcRepository.java
│   │   ├── PostLikeRepository.java
│   │   └── PostRepository.java
│   ├── token
│   │   └── RefreshTokenRepository.java
│   └── user
│       └── UserRepository.java
│
├── security
│   ├── CustomUserDetails.java
│   ├── CustomUserDetailsService.java
│   ├── jwt
│   │   ├── JwtAuthenticationFilter.java
│   │   ├── JwtAuthenticationEntryPoint.java
│   │   ├── JwtUtil.java
│   │   └── JwtAccessDeniedHandler.java
│
├── service
│   ├── auth
│   │   ├── AuthService.java
│   │   └── AuthServiceImpl.java
│   ├── user
│   │   ├── UserService.java
│   │   └── UserServiceImpl.java
│   ├── post
│   │   ├── like
│   │   │   ├── PostLikeService.java
│   │   │   └── PostLikeServiceImpl.java
│   │   ├── viewcount
│   │   │   ├── PostViewService.java
│   │   │   └── PostViewServiceImpl.java
│   │   ├── PostService.java
│   │   └── PostServiceImpl.java
│   ├── s3
│   │   ├── PresignedUrlService.java
│   │   └── PresignedUrlServiceImpl.java
│   └── comment
│   │   ├── CommentService.java
│       └── CommentServiceImpl.java
```
## ERD
<img width="1510" height="602" alt="Copy of erd for git" src="https://github.com/user-attachments/assets/770ef742-972c-4d13-94be-30264909f079" />

## 핵심 기능
### 🔐 인증/인가 - JWT 기반

- Access Token + Refresh Token 구조로 검증 및 로그인
- Access Token 만료 시 Refresh Token으로 재발급
- Refresh Token은 HttpOnly Cookie를 사용해 보안 강화

---
### 🗂️ AWS S3 + Presigned-URL 기반 이미지 업로드

사용 이유
1.	서버 부하 감소: 이미지를 서버로 받지 않고 클라이언트 → S3 직접 업로드
2.	보안성 향상: S3 키를 클라이언트에 직접 노출하지 않음
3.	실시간 업로드 속도 개선: Presigned URL 은 짧은 시간만 유효하며 바로 업로드 가능
4.	서버는 메타데이터만 저장: 객체 키만 DB에 저장해 구조 단순화

적용 방식
- 서버에서 Presigned-URL 생성
- 프론트엔드가 해당 URL로 이미지 업로드
- 업로드된 S3 객체 키를 사용해 이미지 URL 생성 후 게시글/프로필과 연결

---

### ⚡ 조회수 캐싱 + 배치 업데이트 (Spring Cache + Scheduled)

사용 이유
- 게시글 및 사용자가 많아질수록 게시글 조회수 UPDATE 쿼리 폭증 문제(10000번 조회 → 10000번 UPDATE 퀴리) 발생


해결 방법

✔ 1. Spring Cache 에 조회수 저장 (ConcurrentHashMap 기반)
- 게시글 조회 시 DB UPDATE 대신 캐시에서 +1 증가

✔ 2. 일정 주기(1분) 또는 임계치 도달 시 일괄 DB 업데이트
- Scheduler 로 60초마다 캐시 내용을 모두 DB에 반영
- 업데이트는 JDBCTemplate Batch Update를 통해 쿼리 수 최소화

---
## 📄 테스트 코드 작성

본 프로젝트는 안정성 위해 **단위 테스트(Unit Test)**와 **컨트롤러 테스트(MockMvc)** 기반의 검증 체계를 구축했습니다.

### 🧪 테스트 작성 목적

- 신규 기능 추가 시 기존 기능이 깨지지 않도록 보장
- 인증/인가, 캐싱, 예외 처리 등 핵심 로직의 안정성 확보
- 서비스/컨트롤러 계층 역할을 명확히 분리하고 테스트로 보증
- 리팩토링 및 고도화 과정에서 동작 일관성을 유지할 수 있는 기반 마련

---

### 🧱 테스트 구조

### 1) 단위 테스트 (Mockito 기반)

`Service` 레이을에서 의존성을 Mock 처리하여 **비즈니스 로직만 독립적으로 검증**했습니다.

주요 검증 내용:

- 게시글/댓글 CRUD 기능
- 회원가입·로그인 등 인증 로직
- 권한 검증(본인 여부 판단)
- 잘못된 요청 또는 비정상 시나리오에서 예외 발생 여부  
  (Unauthorized, Forbidden, NotFound 등)
- 조회수 캐싱 로직이 DB가 아닌 캐시에 먼저 반영되는지 확인

---

### 2) 컨트롤러 테스트 (MockMvc 기반)

`@WebMvcTest` 환경에서 실제 HTTP 요청과 동일한 방식으로  
**상태 코드, JSON 응답 구조, 메시지, 에러 처리 흐름**을 검증했습니다.

주요 검증 내용:

- 성공 요청 시 응답 메시지·데이터 형식 검증
- 실패 요청 시 올바른 HTTP Status 및 에러 메시지 반환 여부
- 글로벌 예외 처리기 동작 확인
- JWT 인증 필터는 Mock 처리하여 컨트롤러 로직 검증에 집중

---

### 📊 테스트 커버리지(JaCoCo)

JaCoCo를 적용하여 전체 코드 커버리지 및 라인 커버리지를 측정했습니다.

커버리지 확보 범위:

- Service 및 Controller Layer 중심으로 **85% 이상 달성**
- 예외 처리, 인증/인가, 게시글·댓글 CRUD 주요 로직 포함

커버리지 도입 효과:

- 안정적인 리팩토링 가능
- 핵심 기능 품질 보증
- 에러 조기 발견 및 회귀 테스트 강화

결과 이미지:
<img width="1918" height="91" alt="스크린샷 2025-12-09 오후 1 57 40" src="https://github.com/user-attachments/assets/7dbb91d8-731a-4371-9dc7-ee713c7a9cfa" />





---
### 시연 영상

https://github.com/user-attachments/assets/b70d0bb3-5118-4907-900d-cbdb7605dbcb
