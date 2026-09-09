package com.couplemap.memory.repository;

import com.couplemap.memory.domain.UploadSession;
import org.springframework.data.repository.CrudRepository;
import org.springframework.stereotype.Repository;

@Repository
public interface UploadSessionRepository extends CrudRepository<UploadSession, String> {
}
