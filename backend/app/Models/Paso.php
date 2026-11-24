<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;

class Paso extends Model
{
    use HasFactory;

    protected $table = 'pasos';

    protected $fillable = [
        'placa_leida',
        'placa_normalizada',
        'confianza_ocr',
        'categoria_detectada',
        'ejes_detectados',
        'monto',
        'caseta_id',
        'usuario_id',
        'imagen_url',
        'estado',
        'pasajeros',
    ];

    protected $casts = [
        'confianza_ocr' => 'decimal:2',
        'monto' => 'decimal:2',
        'ejes_detectados' => 'integer',
        'pasajeros' => 'integer',
    ];

    public function caseta()
    {
        return $this->belongsTo(Caseta::class);
    }

    public function usuario()
    {
        return $this->belongsTo(User::class, 'usuario_id');
    }

    public function alertas()
    {
        return $this->hasMany(Alerta::class);
    }
}

