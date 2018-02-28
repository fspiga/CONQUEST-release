! Contains routines to evaluate XC energy and potential for radial charge distributions
module radial_xc

contains

  subroutine get_vxc(n_tot,rr,rho,functional,vxc,exc)

    use datatypes
    use numbers
    use GenComms, ONLY: cq_abort
    use global_module, ONLY: functional_lda_pz81, functional_gga_pbe96!, flag_functional_type
    
    implicit none

    ! Passed variables
    integer :: n_tot, functional
    real(double), dimension(n_tot) :: rho, rr,vxc
    real(double), OPTIONAL :: exc
    real(double), allocatable, dimension(:) :: exc_array

    integer :: i
    logical :: flag_energy, flag_libxc ! This will be in global later

    flag_energy = .false.
    if(PRESENT(exc)) then
       flag_energy = .true.
       allocate(exc_array(n_tot))
       exc_array = zero
    end if

    flag_libxc = .false.
    ! Choose LibXC or Conquest
    if(flag_libxc) then
       ! Make derivatives
       ! Call routine
    else
       select case(functional)
       case(functional_lda_pz81)
          if(flag_energy) then
             call vxc_pz_ca(n_tot, rr, rho, vxc, exc_array)
          else
             call vxc_pz_ca(n_tot, rr, rho, vxc)
          end if
       case(functional_gga_pbe96)
          if(flag_energy) then
             call vxc_gga_pbe(n_tot, rr, rho, vxc, exc_array)
          else
             call vxc_gga_pbe(n_tot, rr, rho, vxc)
          end if
       end select
       if(PRESENT(exc)) then
          exc = zero
          do i = 1, n_tot
             exc = exc + exc_array(i)
          end do
          ! Potentially also find Exc correction
       end if
    end if
  end subroutine get_vxc
  
  subroutine vxc_pz_ca(n_tot,rr,rho,vxc,exc)

    use datatypes
    use numbers
    use GenComms, ONLY: cq_abort
    
    implicit none

    ! Passed variables
    integer :: n_tot
    real(double), dimension(n_tot) :: rho, rr,vxc
    real(double), OPTIONAL, dimension(n_tot) :: exc
    
    ! Local variables
    integer :: i
    real(double) :: dx_sq_over_twelve, qtot, V0
    real(double), parameter :: prefac_rs = (three/fourpi)**third
    real(double), parameter :: prefac_vx = (three_halves/pi)**(two*third)
    real(double), dimension(:), allocatable :: y

    real(double) :: denominator, e_correlation, e_exchange, ln_rs, &
                    numerator, rcp_rs, rh, rs, rs_ln_rs, sq_rs
    
    real(double), parameter :: alpha  = -0.45817_double
    real(double), parameter :: beta_1 =  1.0529_double
    real(double), parameter :: beta_2 =  0.3334_double
    real(double), parameter :: gamma  = -0.1423_double
    real(double), parameter :: p =  0.0311_double
    real(double), parameter :: q = -0.048_double
    real(double), parameter :: r =  0.0020_double
    real(double), parameter :: s = -0.0116_double
    
    do i=1,n_tot
       !  rho is 4.pi.rho
       rh = rho(i)/fourpi
       if(rh>1e-8_double) then
          rs = prefac_rs*rh**(-third)
          if(rs>one) then
             sq_rs = sqrt(rs)
             denominator = (one + beta_1 * sq_rs + beta_2 * rs)
             vxc(i) = -prefac_vx/rs + gamma*(one + seven_sixths*beta_1*sq_rs + &
                  four_thirds*beta_2*rs)/(denominator*denominator)
             if(present(exc)) exc(i) = - 0.75_double*prefac_vx/rs + gamma/denominator
          else 
             ln_rs = log(rs)
             vxc(i) = -prefac_vx/rs + p*ln_rs + (q-third*p) + two*third*r*rs*ln_rs + third*(two*s - r)*rs
             if(present(exc)) exc(i) = - 0.75_double*prefac_vx/rs + p*ln_rs + q + r*rs*ln_rs + s*rs
          end if
       else
          vxc(i) = zero
          if(present(exc)) exc(i) = zero
       end if
    end do
  end subroutine vxc_pz_ca

  ! It's not necessary to calculate the full set of arrays of derivatives etc for this simple GGA
  ! implementation - we can simply do it point by point (as it's one dimensional).
  subroutine vxc_gga_pbe(n_tot,rr,rho,vxc,exc)

    use datatypes
    use numbers
    use GenComms, ONLY: cq_abort
    use mesh, ONLY: drdi, alpha, drdi_squared
    
    implicit none

    ! Passed variables
    integer :: n_tot
    real(double), dimension(n_tot) :: rho, rr,vxc
    real(double), dimension(n_tot), OPTIONAL :: exc

    ! Local variables
    ! rho/4pi, differentials wrt grid (n) and radius (r) and laplacian
    real(double) :: rho_sc, drho_dn, d2rho_dn2, drho_dr, d2rho_dr2, lapl_rho
    real(double), parameter :: thirty = 30.0_double
    real(double), parameter :: prefac_rs = (three/fourpi)**third
    real(double), parameter :: prefac_kf = (three *pi*pi)**third
    ! Parameters for GGA routines
    real(double) :: kF, s, t, u, v, rs, zeta, k_s
    ! GGA exchange energy and potential
    real(double) :: ex, vx, ec, vc, h, dvc

    integer :: i
    
    ! Work on main part first (where we can use FD) and add ends later
    do i=3,n_tot-2
       !  rho is 4.pi.rho
       rho_sc = rho(i)/fourpi
       ! Five point finite differences for differential wrt mesh points (not r)
       ! First derivative - extra factor of 4pi to scale rho
       drho_dn   = ( rho(i-2) -   eight*rho(i-1) + eight*rho(i+1) - rho(i+2))/(twelve*fourpi)
       ! Second derivative - extra factor of 4pi to scale rho
       d2rho_dn2 = (-rho(i-2) + sixteen*rho(i-1) -thirty*rho(i) + sixteen*rho(i+1) - rho(i+2))/(twelve*fourpi)
       ! Now differential wrt r
       drho_dr   = drho_dn/(drdi(i))
       ! NB the alpha here is from the radial mesh (NOT the alpha defined in the PW92 LDA correlation)
       d2rho_dr2 = (d2rho_dn2 - alpha*drho_dn)/drdi_squared(i)
       lapl_rho  = (d2rho_dn2 + alpha*drho_dn)/drdi_squared(i)
       if(rho_sc>1e-10_double) then ! Hamann's tolerance - check
          kF = prefac_kF*rho_sc**third
          s = abs(drho_dr)/(two * kF * rho_sc)
          u = abs(drho_dr)*d2rho_dr2/(rho_sc*rho_sc*eight*kF*kF*kF)
          v = lapl_rho/(rho_sc*four*kF*kF)
          call pbe_exch(rho_sc,s,u,v,ex,vx)
          rs = prefac_rs*rho_sc**(-third)
          k_s = sqrt(four*kF/pi) ! NB a0 = 1 as we use atomic units
          zeta = zero
          t = abs(drho_dr)/(two*k_s*rho_sc) ! Set phi = one as zeta = zero
          ! Redefine u and v with k_s instead of k_F
          u = abs(drho_dr)*d2rho_dr2/(rho_sc*rho_sc*eight*k_s*k_s*k_s)
          v = lapl_rho/(rho_sc*four*k_s*k_s)
          call pbe_corr(rs,t,u,v,ec,vc,h,dvc) ! No spin
       else
          vx = zero
          vc = zero
          dvc = zero
          ex = zero
          ec = zero
          h = zero
       end if
       vxc(i) = vx + vc + dvc
       if(PRESENT(exc)) exc(i) = ex + ec + h
    end do
    ! Assume that the end points are essentially constant
    vxc(1) = vxc(3)
    vxc(2) = vxc(3)
    vxc(n_tot-1) = vxc(n_tot-2)
    vxc(n_tot)   = vxc(n_tot-2)
    if(PRESENT(exc)) then
       exc(1) = exc(3)
       exc(2) = exc(3)
       exc(n_tot-1) = exc(n_tot-2)
       exc(n_tot)   = exc(n_tot-2)
    end if
    return
  end subroutine vxc_gga_pbe

  ! From the original PBE routines
  subroutine pbe_exch(rho, s, u, v, ex, vx)

    use datatypes
    use numbers
    
    implicit none

    ! Passed variables
    real(double) :: rho, s, u, v, ex, vx

    ! Precalculated constants
    real(double), parameter :: prefac_ex = -three_quarters * (3/pi)**third 
    real(double), parameter :: mu = 0.2195149727645171_double ! beta (pi^2)/3 (Eq 12 in paper)
    real(double), parameter :: kappa = 0.804_double

    ! Local variables
    real(double) :: ex_lda, ul, p0, Fx, dFds, d2Fds2

    ul = mu/kappa
    ! ------
    ! Energy
    ! ------
    ! LDA exchange
    ex_lda = prefac_ex * rho**third
    ! PBE enhancement
    p0 = one + ul * s * s
    Fx = one + kappa - kappa / p0
    ex = ex_lda * Fx
    ! ---------
    ! Potential
    ! ---------
    ! Derivatives of Fx wrt s: dFds = (1/s)dF/ds; d2Fds2 = d(dFds)/ds
    dFds = two * mu / (p0 * p0)
    d2Fds2 = -four * ul * s * dFds / p0
    vx = ex_lda * (four * third * Fx - (u - four * third * s * s * s)*d2Fds2 - v * dFds)
  end subroutine pbe_exch

  subroutine pbe_corr(rs, t, u, v, ec_unif, vc_unif, h, dvc)

    use datatypes
    use numbers
    
    implicit none

    ! Passed variables
    real(double) :: rs, t, u, v, ec_unif, vc_unif, h, dvc ! Seitz radius !

    ! Local variables
    real(double) :: sq_rs, prefac_ec_lda, log_fac_ec_lda, denominator
    real(double) :: d_prefac_ec_lda, d_log_fac_ec_lda, d_denom_drs
    real(double) :: t2, t4, t6
    real(double) :: F1, F2, A, F3, F4, F6, ec_rs
    real(double) :: A2, bg, bec, F5, F8, F9, h_A, h_rs, fact0, fact1, h_BT, h_RST, h_T, fact2, fact3, h_TT
    ! Precalculated constants
    real(double), parameter :: prefac_ex = -three_quarters * (3/pi)**third
    real(double), parameter :: k02 = -0.062182_double       ! -2*A
    real(double), parameter :: k03 = -0.0132882934_double   ! -2*A*alpha1
    real(double), parameter :: k04 = 0.4723158174_double    ! 2*A*beta1
    real(double), parameter :: k05 = 0.2230841432_double    ! 2*A*beta2
    real(double), parameter :: k06 = 0.1018665524_double    ! 2*A*beta3
    real(double), parameter :: k07 = 0.03065199508_double   ! 2*A*beta4
    real(double), parameter :: k08 = -0.008858862267_double ! 2*k03/3
    real(double), parameter :: k09 = 0.0787193029_double    ! k04/6
    real(double), parameter :: k10 = 0.074361381067_double  ! k05/3
    real(double), parameter :: k11 = 0.0509332762_double    ! k06/2
    real(double), parameter :: k12 = 0.0204346633867_double ! 2*k07/3
    real(double), parameter :: beta = 0.066725_double
    real(double), parameter :: gamma = 0.031091_double
    real(double), parameter :: beta_gamma = 2.146119_double    ! beta/gamma

    sq_rs = sqrt(rs)

    ! Local correlation energy Eq 10 PRB 45, 13244
    prefac_ec_lda = k02 + k03*rs
    denominator = sq_rs * ( k04 + sq_rs * ( k05 + sq_rs * ( k06 + k07 * sq_rs)))
    if (denominator > zero) then
       log_fac_ec_lda = log( one + one/denominator )
    else
       log_fac_ec_lda = 0
    end if
    ec_unif = prefac_ec_lda * log_fac_ec_lda

    ! Non-local correlation energy
    ! Original Conquest routines adapted from PRL 77 3865 and PRB 45 13244
    F1 = ec_unif / gamma ! -PON 
    F2 = exp(-F1)        
    ! This is the variable A from the PBE paper Eq 8, NOT the constant in PW92 ! 
    A = beta_gamma / (F2 - one + RD_ERR) ! B in Burke's code
    t2 = t*t
    t4 = t2*t2
    F3 = t2 + A * t4 ! Q5 = 1+A*F3 in Burke; Q4 * t2 = F3 in Burke
    F6 = one + A * F3 !Q5
    F4 = beta_gamma * F3 / F6 !(one + A * F3)
    ! Eq 7 with phi = 1, atomic units
    h = gamma * log(one + F4) 

    ! Local correlation potential
    ! ECRS - dec_drs for LDA from PW92 Appendix A
    ! rtrs == sq_rs
    ! Q0 == prefac_ec_lda 
    ! Q1 == denominator 
    ! Q2 == log_fac_ec_lda
    ! Q3 = A*(B1/rtrs + two*B2 + rtrs*(three*B3 + four*B4*rtrs))
    !    = half*sq_rs*(2A*B1 + 2*2A*B2*sq_rs + 3*2A*B3*rs + 4*2A*B4*rs*sq_rs  )/rs
    !    = half*(k04 + sq_rs*(two*k05 + sq_rs*(three*k06 + four*k07*sq_rs)))/sq_rs
    ! dec_drs = -2A * A1 * Q2 - Q0 * Q3 /(Q1*(one + Q1))
    d_denom_drs = half * (k04 + sq_rs * ( two * k05 + sq_rs * ( three * k06 + four * k07 * sq_rs)))/sq_rs
    ec_rs = k03 * log_fac_ec_lda - prefac_ec_lda * d_denom_drs / (denominator * (one + denominator)) 
    vc_unif = ec_unif - rs * third * ec_rs
    
    ! Non-local correlation potential
    t6 = t2*t4
    ! In Burke's routines,
    !   delt = beta/gamma which is beta_gamma here
    !   G is one if non-spin; F is zero if non-spin
    !   Q4 = 1 + A * t2
    !   GZ = zero if non-spin, as are FZ and ECZET
    A2 = A*A
    bg = -three * A2 * ec_unif * F2/beta
    bec = A2*F2/beta
    F5 = one + A * t2 !Q4
    F8 = F6 * F6 + beta_gamma * F5 * F6 * t2! Q8
    F9 = one + two * A * t2     ! Q9
    h_A = -beta * A * t6 * (two + A * t2) / F8
    h_rs = -third * rs * h_A * bec * ec_rs
    fact0 = two*beta_gamma - six * A ! FACT0
    fact1 = F6 * F9 + F5 * F9 * F9 !      FACT1 = Q5*Q9+Q4*Q9*Q9
    h_BT = two * beta * t4 * (F5 * F6 * fact0 - beta_gamma * fact1)/(F8 * F8)
    h_RST = third * rs * t2 * h_BT * bec * ec_rs ! RSTHRD*T2*hBT*BEC*ECRS
    h_T = two * beta * F9/F8 !2.d0*BET*G3*Q9/Q8
    fact2 = F5 * F6 + A * t2 * (F5 * F9 + F6) !FACT2 = Q4*Q5+B*T2*(Q4*Q9+Q5)
    fact3 = two * A * F6 * F9 + beta_gamma * fact2 !FACT3 = 2.D0*B*Q5*Q9+DELT*FACT2
    h_TT = four * beta * t * (two * A - F9*fact3/F8)/F8 !hTT = 4.D0*BET*G3*T*(2.D0*B/Q8-(Q9*FACT3/Q8)/Q8)
    ! Derivative wrt n (I'm pretty sure)
    dvc = H + h_rs + h_RST + t2 * h_t / six + seven * t2 * t * h_TT / six !COMM = H+HRS+HRST+T2*HT/6.D0+7.D0*T2*T*HTT/6.D0
    ! Derivative wrt grad n (again, I'm pretty sure)
    dvc = dvc - u * h_TT - v * h_T !COMM = COMM-PREF*ZET-UU*HTT-VV*HT-WW*(HZT-FACT5)
    
    ! These are Conquest lines which I will adapt and use to tidy the mess above later !
    ! Correlation
    !   (derivative of rho * e_correlation)
    ! NOTE: d_prefac_ec_lda is actually the derivative of rho*prefac_ec_lda
    !       d_log_fac_ec_lda is rho times the derivative of log_fac_ec_lda
    !d_prefac_ec_lda  = k02 + k08*rs
    !if (sq_rs > zero) then
    !   d_log_fac_ec_lda = &
    !        sq_rs * (k09 + sq_rs*(k10 + sq_rs*(k11 + k12 * sq_rs))) / &
    !        (denominator * (1 + denominator))
    !else
    !   d_log_fac_ec_lda = 0
    !end if
    !vc = d_prefac_ec_lda * log_fac_ec_lda + prefac_ec_lda * d_log_fac_ec_lda
    !if (present(drhoEps_c)) then
    !   drs_drho = - (third * rs / rho_tot_r)
    !   dkF_drho = third * kF / rho_tot_r
    !   dks_drho = half * ks * dkF_drho / kF
    !   deps_c_unif_drho = (Vc_unif(1) - eps_c_unif) / rho_tot_r
    !   dt_drho = (- t) * (dks_drho / ks + one / rho_tot_r)
    !   ! add RD_ERR to denominator to avoid div by 0
    !   dF1_drho = F1 * (deps_c_unif_drho / (eps_c_unif + RD_ERR))
    !   dF2_Drho = (- F2) * dF1_drho
    !   ! add RD_ERR to denominator to avoid div by 0
    !   dA_drho = A * dF2_drho / (one - F2 + RD_ERR)
    !   dF3_drho = (two * t + four * A * t**3) * dt_drho + dA_drho * t**4
    !   dF4_drho = F4 * (dF3_drho / F3 - &
    !        (dA_drho * F3 + A * DF3_drho) / (one + A * F3))
    !
    !   dH_drho = gamma * DF4_drho / (one + F4)
    !
    !   ! get drhoEps_c / drho(spin)
    !   drhoEps_c(0,1) = Vc_unif(1) + H + rho_tot_r * dH_drho
    !   do ii = 1, 3
    !      dt_dgrho = (t / mod_grho_tot_r) * grho_tot_r(ii) / mod_grho_tot_r
    !      dF3_dgrho = dt_dgrho * (two * t + four * A * t**3)
    !      dF4_dgrho = F4 * dF3_dgrho * (one / F3 - A / (one + A * F3))
    !      dH_dgrho = gamma * dF4_dgrho / (one + F4)
    !      drhoEps_c(ii,1) = rho_tot_r * dH_dgrho
    !   end do
    !end if ! present(drhoEps_c)
    
  end subroutine pbe_corr

end module radial_xc
