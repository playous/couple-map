package com.couplemap.memory.domain;

import com.couplemap.global.common.BaseEntity;
import com.couplemap.map.domain.Map;
import com.couplemap.memory.dto.CreateMemoryRequestDto;
import com.couplemap.memory.dto.UpdateMemoryRequestDto;
import com.couplemap.user.domain.User;
import jakarta.persistence.*;
import lombok.AccessLevel;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;

import java.math.BigDecimal;
import java.time.LocalDate;

@Entity
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
@Table(name = "memories", indexes =
        @Index(name = "idx_memories_map_id_memory_date", columnList = "map_id, memory_date"))
public class Memory extends BaseEntity {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    @Column(name = "memory_id")
    private Long memoryId;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "map_id", nullable = false, foreignKey = @ForeignKey(name = "fk_memories_map"))
    private Map map;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "user_id", nullable = false, foreignKey = @ForeignKey(name = "fk_memories_user"))
    private User user;

    @Column(name = "title", nullable = false, length = 50)
    private String title;

    @Column(name = "content", length = 100)
    private String content;

    @Column(name = "place_name", nullable = false)
    private String placeName;

    @Column(name = "address")
    private String address;

    @Column(name = "memory_date", nullable = false)
    private LocalDate memoryDate;

    @Column(name = "latitude", nullable = false, precision = 10, scale = 8)
    private BigDecimal latitude;

    @Column(name = "longitude", nullable = false, precision = 11, scale = 8)
    private BigDecimal longitude;

    @Column(name = "category")
    private String category;

    @Builder
    private Memory(Map map, User user, String title, String content, String placeName, String address, LocalDate memoryDate, BigDecimal latitude, BigDecimal longitude, String category) {
        this.map = map;
        this.user = user;
        this.title = title;
        this.content = content;
        this.placeName = placeName;
        this.address = address;
        this.memoryDate = memoryDate;
        this.latitude = latitude;
        this.longitude = longitude;
        this.category = category;
    }

    public static Memory from(CreateMemoryRequestDto request, Map map, User user) {
        return Memory.builder()
                .map(map)
                .user(user)
                .title(request.getTitle())
                .content(request.getContent())
                .placeName(request.getPlaceName())
                .address(request.getAddress())
                .memoryDate(request.getMemoryDate())
                .latitude(request.getLatitude())
                .longitude(request.getLongitude())
                .category(request.getCategory())
                .build();
    }

    public void update(UpdateMemoryRequestDto request) {
        this.title = request.getTitle();
        this.content = request.getContent();
        this.placeName = request.getPlaceName();
        this.memoryDate = request.getMemoryDate();
        this.category = request.getCategory();
    }
}
