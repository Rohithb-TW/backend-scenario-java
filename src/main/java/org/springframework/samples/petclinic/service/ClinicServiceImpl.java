/*
 * Copyright 2002-2017 the original author or authors.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
package org.springframework.samples.petclinic.service;

import org.springframework.cache.annotation.CacheEvict;
import org.springframework.cache.annotation.Cacheable;
import org.springframework.cache.annotation.Caching;
import org.springframework.dao.DataAccessException;
import org.springframework.dao.EmptyResultDataAccessException;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.orm.ObjectRetrievalFailureException;
import org.springframework.samples.petclinic.model.*;
import org.springframework.samples.petclinic.repository.*;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.Collection;
import java.util.List;
import java.util.Set;
import java.util.function.Supplier;

/**
 * Mostly used as a facade for all Petclinic controllers
 * Also a placeholder for @Transactional and @Cacheable annotations
 *
 * <p>Caching strategy:
 * <ul>
 *   <li>{@code @Cacheable} is applied to collection-level reads ({@code findAll*},
 *       {@code findPetTypes}, {@code findOwnerByLastName}, {@code findVisitsByPetId})
 *       which are high-frequency and stable between writes.</li>
 *   <li>Single-entity by-ID lookups are intentionally NOT cached to avoid
 *       stale data after {@code @Transactional} test rollbacks.</li>
 *   <li>{@code @CacheEvict(beforeInvocation = true)} is used on all write/delete
 *       methods so that subsequent reads within the same transaction always
 *       bypass the cache and fetch fresh data from the database.</li>
 * </ul>
 *
 * @author Michael Isvy
 * @author Vitaliy Fedoriv
 */
@Service
public class ClinicServiceImpl implements ClinicService {

    private final PetRepository petRepository;
    private final VetRepository vetRepository;
    private final OwnerRepository ownerRepository;
    private final VisitRepository visitRepository;
    private final SpecialtyRepository specialtyRepository;
    private final PetTypeRepository petTypeRepository;

    public ClinicServiceImpl(
        PetRepository petRepository,
        VetRepository vetRepository,
        OwnerRepository ownerRepository,
        VisitRepository visitRepository,
        SpecialtyRepository specialtyRepository,
        PetTypeRepository petTypeRepository) {
        this.petRepository = petRepository;
        this.vetRepository = vetRepository;
        this.ownerRepository = ownerRepository;
        this.visitRepository = visitRepository;
        this.specialtyRepository = specialtyRepository;
        this.petTypeRepository = petTypeRepository;
    }

    // -------------------------------------------------------------------------
    // Pet methods
    // -------------------------------------------------------------------------

    @Override
    @Transactional(readOnly = true)
    @Cacheable("pets")
    public Collection<Pet> findAllPets() throws DataAccessException {
        return petRepository.findAll();
    }

    @Override
    @Transactional(readOnly = true)
    public Page<Pet> findPets(Pageable pageable) throws DataAccessException {
        return petRepository.findAll(pageable);
    }

    @Override
    @Transactional(readOnly = true)
    public Pet findPetById(int id) throws DataAccessException {
        return findEntityById(() -> petRepository.findById(id));
    }

    @Override
    @Transactional
    @Caching(evict = {
        @CacheEvict(value = "pets", allEntries = true, beforeInvocation = true),
        @CacheEvict(value = "owners", allEntries = true, beforeInvocation = true)
    })
    public void savePet(Pet pet) throws DataAccessException {
        pet.setType(findPetTypeById(pet.getType().getId()));
        petRepository.save(pet);
    }

    @Override
    @Transactional
    @Caching(evict = {
        @CacheEvict(value = "pets", allEntries = true, beforeInvocation = true),
        @CacheEvict(value = "owners", allEntries = true, beforeInvocation = true)
    })
    public void deletePet(Pet pet) throws DataAccessException {
        petRepository.delete(pet);
    }

    // -------------------------------------------------------------------------
    // Visit methods
    // -------------------------------------------------------------------------

    @Override
    @Transactional(readOnly = true)
    public Visit findVisitById(int visitId) throws DataAccessException {
        return findEntityById(() -> visitRepository.findById(visitId));
    }

    @Override
    @Transactional(readOnly = true)
    @Cacheable("visits")
    public Collection<Visit> findAllVisits() throws DataAccessException {
        return visitRepository.findAll();
    }

    @Override
    @Transactional(readOnly = true)
    @Cacheable(value = "visits", key = "'byPet_' + #petId")
    public Collection<Visit> findVisitsByPetId(int petId) {
        return visitRepository.findByPetId(petId);
    }

    @Override
    @Transactional
    @CacheEvict(value = "visits", allEntries = true, beforeInvocation = true)
    public void saveVisit(Visit visit) throws DataAccessException {
        visitRepository.save(visit);
    }

    @Override
    @Transactional
    @CacheEvict(value = "visits", allEntries = true, beforeInvocation = true)
    public void deleteVisit(Visit visit) throws DataAccessException {
        visitRepository.delete(visit);
    }

    // -------------------------------------------------------------------------
    // Vet methods
    // -------------------------------------------------------------------------

    @Override
    @Transactional(readOnly = true)
    public Vet findVetById(int id) throws DataAccessException {
        return findEntityById(() -> vetRepository.findById(id));
    }

    @Override
    @Transactional(readOnly = true)
    @Cacheable("vets")
    public Collection<Vet> findAllVets() throws DataAccessException {
        return vetRepository.findAll();
    }

    @Override
    @Transactional(readOnly = true)
    @Cacheable("vets")
    public Collection<Vet> findVets() throws DataAccessException {
        return vetRepository.findAll();
    }

    @Override
    @Transactional
    @CacheEvict(value = "vets", allEntries = true, beforeInvocation = true)
    public void saveVet(Vet vet) throws DataAccessException {
        vetRepository.save(vet);
    }

    @Override
    @Transactional
    @CacheEvict(value = "vets", allEntries = true, beforeInvocation = true)
    public void deleteVet(Vet vet) throws DataAccessException {
        vetRepository.delete(vet);
    }

    // -------------------------------------------------------------------------
    // Owner methods
    // -------------------------------------------------------------------------

    @Override
    @Transactional(readOnly = true)
    @Cacheable("owners")
    public Collection<Owner> findAllOwners() throws DataAccessException {
        return ownerRepository.findAll();
    }

    @Override
    @Transactional(readOnly = true)
    public Page<Owner> findOwners(String lastName, Pageable pageable) throws DataAccessException {
        if (lastName != null) {
            return ownerRepository.findByLastName(lastName, pageable);
        }
        return ownerRepository.findAll(pageable);
    }

    @Override
    @Transactional(readOnly = true)
    public Owner findOwnerById(int id) throws DataAccessException {
        return findEntityById(() -> ownerRepository.findById(id));
    }

    @Override
    @Transactional(readOnly = true)
    @Cacheable(value = "owners", key = "'byLastName_' + #lastName")
    public Collection<Owner> findOwnerByLastName(String lastName) throws DataAccessException {
        return ownerRepository.findByLastName(lastName);
    }

    @Override
    @Transactional
    @CacheEvict(value = "owners", allEntries = true, beforeInvocation = true)
    public void saveOwner(Owner owner) throws DataAccessException {
        ownerRepository.save(owner);
    }

    @Override
    @Transactional
    @CacheEvict(value = "owners", allEntries = true, beforeInvocation = true)
    public void deleteOwner(Owner owner) throws DataAccessException {
        ownerRepository.delete(owner);
    }

    // -------------------------------------------------------------------------
    // PetType methods
    // -------------------------------------------------------------------------

    @Override
    @Transactional(readOnly = true)
    public PetType findPetTypeById(int petTypeId) {
        return findEntityById(() -> petTypeRepository.findById(petTypeId));
    }

    @Override
    @Transactional(readOnly = true)
    @Cacheable("petTypes")
    public Collection<PetType> findAllPetTypes() throws DataAccessException {
        return petTypeRepository.findAll();
    }

    @Override
    @Transactional(readOnly = true)
    @Cacheable("petTypes")
    public Collection<PetType> findPetTypes() throws DataAccessException {
        return petRepository.findPetTypes();
    }

    @Override
    @Transactional
    @CacheEvict(value = "petTypes", allEntries = true, beforeInvocation = true)
    public void savePetType(PetType petType) throws DataAccessException {
        petTypeRepository.save(petType);
    }

    @Override
    @Transactional
    @CacheEvict(value = "petTypes", allEntries = true, beforeInvocation = true)
    public void deletePetType(PetType petType) throws DataAccessException {
        petTypeRepository.delete(petType);
    }

    // -------------------------------------------------------------------------
    // Specialty methods
    // -------------------------------------------------------------------------

    @Override
    @Transactional(readOnly = true)
    public Specialty findSpecialtyById(int specialtyId) {
        return findEntityById(() -> specialtyRepository.findById(specialtyId));
    }

    @Override
    @Transactional(readOnly = true)
    @Cacheable("specialties")
    public Collection<Specialty> findAllSpecialties() throws DataAccessException {
        return specialtyRepository.findAll();
    }

    @Override
    @Transactional(readOnly = true)
    public List<Specialty> findSpecialtiesByNameIn(Set<String> names) {
        return findEntityById(() -> specialtyRepository.findSpecialtiesByNameIn(names));
    }

    @Override
    @Transactional
    @CacheEvict(value = "specialties", allEntries = true, beforeInvocation = true)
    public void saveSpecialty(Specialty specialty) throws DataAccessException {
        specialtyRepository.save(specialty);
    }

    @Override
    @Transactional
    @CacheEvict(value = "specialties", allEntries = true, beforeInvocation = true)
    public void deleteSpecialty(Specialty specialty) throws DataAccessException {
        specialtyRepository.delete(specialty);
    }

    // -------------------------------------------------------------------------
    // Internal helpers
    // -------------------------------------------------------------------------

    private <T> T findEntityById(Supplier<T> supplier) {
        try {
            return supplier.get();
        } catch (ObjectRetrievalFailureException | EmptyResultDataAccessException e) {
            // Just ignore not found exceptions for Jdbc/Jpa realization
            return null;
        }
    }

}
